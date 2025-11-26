`include "sys_defs.svh"

module lq #(
    parameter int DISPATCH_WIDTH = 1,
    parameter int LQ_SIZE = 16,
    parameter int SQ_SIZE = 16,
    parameter int IDX_WIDTH = $clog2(LQ_SIZE)
)
(   
    input logic clock, reset,

    // 1. Enqueue (Dispatch)
    input logic         enq_valid, 
    input ADDR          enq_addr,
    input MEM_SIZE      enq_size,
    input ROB_IDX       enq_rob_idx,
    output logic        full,

    // 2. SQ Forwarding (Query & Response)
    input  logic       sq_forward_valid,
    input  MEM_BLOCK   sq_forward_data,
    input  ADDR        sq_forward_addr, // 其實如果是針對特定 query 回覆，addr 可以不用 check
    input  logic       sq_fwd_pending,
    output ADDR        sq_query_addr,
    output MEM_SIZE    sq_query_size,

    // 3. D-Cache Request
    output logic       dc_req_valid,
    output ADDR        dc_req_addr,
    output MEM_SIZE    dc_req_size,
    input  logic       dc_req_accept,
    output logic [IDX_WIDTH-1:0] dc_req_tag,

    // 4. D-Cache Response
    input  MEM_BLOCK   dc_load_data,
    input  logic       dc_load_valid,
    input  logic [IDX_WIDTH-1:0] dc_load_tag,

    // 5. Writeback (To CDB/ROB - Data Ready)
    input  ROB_IDX     rob_head,
    output logic       wb_valid,
    output ROB_IDX     wb_rob_idx,
    output MEM_BLOCK   wb_data,

    // 6. Commit (From ROB - Free Entry)
    input  logic       rob_commit_valid,
    input  ROB_IDX     rob_commit_valid_idx,

    output logic       empty,

    // Snapshot interface (Keep as is)
    input logic [DISPATCH_WIDTH-1:0] is_branch_i,
    input logic                      snapshot_restore_valid_i,
    output logic                     checkpoint_valid_o,
    output lq_entry_t                snapshot_data_o[LQ_SIZE-1:0],
    output logic   [IDX_WIDTH-1 : 0] snapshot_head_o , snapshot_tail_o,
    output logic   [$clog2(LQ_SIZE+1)-1:0] snapshot_count_o,
    input lq_entry_t                 snapshot_data_i[LQ_SIZE-1:0],
    input logic    [IDX_WIDTH-1 : 0] snapshot_head_i , snapshot_tail_i,
    input logic   [$clog2(LQ_SIZE+1)-1:0] snapshot_count_i,

    input sq_entry_t sq_view_i [SQ_SIZE-1:0]
);

    // Function for pointer increment
    function automatic [IDX_WIDTH-1:0] next_ptr(input [IDX_WIDTH-1:0] ptr);
        return (ptr == LQ_SIZE-1) ? 0 : ptr + 1;
    endfunction

    lq_entry_t lq[LQ_SIZE];
    logic [IDX_WIDTH-1 : 0] head, tail;
    logic [$clog2(LQ_SIZE+1)-1:0] count;
    
    assign full = (count == LQ_SIZE);
    assign empty = (count == 0);

    // Snapshot logic
    logic checkpoint_valid_next;
    always_comb begin 
        checkpoint_valid_next = 1'b0;
        for(int i =0 ; i < DISPATCH_WIDTH ; i++) begin
            if(is_branch_i[i]) begin
                checkpoint_valid_next = 1'b1;
                break;
            end
        end        
    end

    // =========================================================================
    // Combinational Logic: Find Candidate for Forwarding Query & Issue
    // =========================================================================
    logic found_unissued;
    logic [IDX_WIDTH-1:0] query_idx; // 記住是誰在查詢
    logic stall_older_store_unknown;

    always_comb begin
        int i;
        int idx;
        found_unissued = 1'b0;
        query_idx = '0;
        sq_query_addr = '0;
        sq_query_size = '0;
        stall_older_store_unknown = 1'b0;
        // Find the oldest valid entry that needs data (not valid, not issued)
        // This acts as the candidate for BOTH Forwarding and D-Cache Issue
        for(i = 0; i < LQ_SIZE; i++) begin
            idx = (head + i) % LQ_SIZE; // Check from oldest to youngest
            if(lq[idx].valid && !lq[idx].data_valid) begin
                sq_query_addr = lq[idx].addr;
                sq_query_size = lq[idx].size;
                query_idx = idx;
                found_unissued = 1'b1;
                break; // Found the oldest one
            end
        end
    end

    // =========================================================================
    // Combinational Logic: D-Cache Request
    // =========================================================================
    always_comb begin
        dc_req_valid = 1'b0;
        dc_req_addr  = '0;
        dc_req_size  = '0;
        $display("[DEBUG-ALWAYS LOAD QUEUE] Count=%0d, Tail=%0d, Head=%0d", count, tail, head);

        // 只有當準備 Issue 時才檢查
        if (found_unissued) begin
            // 掃描整個 SQ
            for (int k=0; k<SQ_SIZE; k++) begin
                // 條件：SQ有效 + 地址未知 + 比目前的 Load 老
                if (sq_view_i[k].valid && 
                    !sq_view_i[k].addr_valid && 
                    is_older(sq_view_i[k].rob_idx, lq[query_idx].rob_idx, rob_head)) begin
                    
                    stall_older_store_unknown = 1'b1;
                    break; // 只要有一個擋路，就必須停
                end
            end
        end

        // Only issue request if:
        // 1. We found a candidate (found_unissued)
        // 2. SQ is NOT saying "Wait, I have data pending" (sq_fwd_pending)
        // 3. SQ is NOT immediately providing data (sq_forward_valid) -> optimization
        if (found_unissued && !stall_older_store_unknown && !sq_fwd_pending && !sq_forward_valid) begin
            dc_req_valid = 1'b1;
            dc_req_addr  = sq_query_addr; // Same as lq[query_idx].addr
            dc_req_size  = sq_query_size;
            dc_req_tag   = query_idx;
            $display("dc_req_valid: %0b , dc_req_addr: %0h ,dc_req_size: %0d, dc_req_tag:%0d " ,dc_req_valid,dc_req_addr,dc_req_size, dc_req_tag);
        end
    end

    // =========================================================================
    // Sequential Logic: State Updates
    // =========================================================================
    always_ff @(posedge clock) begin
        logic do_enq, do_commit;
        logic wb_from_fwd, wb_from_cache;
        if(reset) begin
            head <= '0;
            tail <= '0;
            count <= '0;
            checkpoint_valid_o <= 1'b0;
            wb_valid <= 1'b0;
            wb_rob_idx <= '0;
            wb_data <= '0;
            for(int i = 0; i < LQ_SIZE; i++) begin
                lq[i].valid <= '0;
                lq[i].data_valid <= '0;
                lq[i].issued <= '0;
                // Initialize other fields to 0 or X
                lq[i].addr <= '0;
                lq[i].size <= '0;
                lq[i].rob_idx <= '0;
                lq[i].data <= '0;
            end
        end else begin
            checkpoint_valid_o <= checkpoint_valid_next;
            wb_valid <= 1'b0; // Default: Pulse wb_valid high for 1 cycle only
            wb_data <= '0;

            // 定義動作
            do_enq = enq_valid && !full;
            // 只有在 Valid 且符合 ROB Index 時才 Commit
            do_commit = !empty && lq[head].valid && rob_commit_valid && (rob_commit_valid_idx == lq[head].rob_idx);

            // 定義 WB 來源
            wb_from_cache = dc_load_valid;
            // 只有當 Cache 沒有佔用 WB 通道時，才允許 Forwarding WB
            // 否則我們這回合先不收 Forwarding data (下回合再收)
            wb_from_fwd   = found_unissued && sq_forward_valid && !wb_from_cache;

            if (do_enq && !do_commit)      count <= count + 1'b1;
            else if (!do_enq && do_commit) count <= count - 1'b1;

            if(snapshot_restore_valid_i) begin
                // ... Snapshot Restore (Keep original logic) ...
                head <= snapshot_head_i;
                tail <= snapshot_tail_i;
                count <= snapshot_count_i;
                for(int i = 0; i < LQ_SIZE; i++) begin
                    lq[i] <= snapshot_data_i[i];
                end
            end else begin
                
                // ------------------------------------
                // 1. Enqueue
                // ------------------------------------
                if(enq_valid && !full) begin
                    lq[tail].valid <= 1'b1;
                    lq[tail].addr <= enq_addr;
                    lq[tail].size <= enq_size;
                    lq[tail].rob_idx <= enq_rob_idx;
                    lq[tail].data_valid <= 1'b0;
                    lq[tail].issued <= 1'b0;
                    tail <= next_ptr(tail);
                    // count <= count + 1'b1;
                end

                if(wb_from_cache) begin
                    // 簡單版本：搜尋第一個 issued 但沒資料的
                    // 進階版本：D-Cache 應該回傳 Tag/Index
                    // for(int i = 0; i < LQ_SIZE; i++) begin
                    //     int idx = (head + i) % LQ_SIZE;
                    //     if(lq[idx].valid && lq[idx].issued && !lq[idx].data_valid) begin
                    //         lq[idx].data <= dc_load_data;
                    //         lq[idx].data_valid <= 1'b1;
                    //         break; // Assume strictly in-order return for this simple logic
                    //     end
                    // end
                    lq[dc_load_tag].data       <= dc_load_data;
                    lq[dc_load_tag].data_valid <= 1'b1;

                    // modify by zhengge in 11/25 TODO
                    wb_valid   <= 1'b1;
                    wb_rob_idx <= lq[dc_load_tag].rob_idx; // 注意：要確認 tag 對應的 rob_idx 正確
                    wb_data    <= dc_load_data;
                end
                // ------------------------------------
                // 2. Handling SQ Forwarding Response
                // ------------------------------------
                // If we queried SQ and it says "Hit!", take the data directly
                else if(wb_from_fwd) begin
                    // 直接寫入剛剛發起查詢的那個 Index (query_idx)
                    $display("sq_forwarding");
                    lq[query_idx].data <= sq_forward_data;
                    lq[query_idx].data_valid <= 1'b1;
                    // 不需要 set issued, 因為資料已經拿到了
                    // Trigger Writeback immediately (Optional, or wait for next cycle logic)
                    // 為了簡化，我們讓它在下個 cycle 透過一般 Writeback 邏輯處理，
                    // 或者在這裡直接觸發 wb_valid 也可以。
                    wb_valid   <= 1'b1;
                    wb_rob_idx <= lq[query_idx].rob_idx;
                    wb_data    <= sq_forward_data;
                end

                // ------------------------------------
                // 3. Handling D-Cache Request Accepted
                // ------------------------------------
                // Mark as issued so we don't request again
                // if(dc_req_valid && dc_req_accept) begin
                //     lq[query_idx].issued <= 1'b1;
                // end

                // ------------------------------------
                // 4. Handling D-Cache Data Return
                // ------------------------------------

                // ------------------------------------
                // 5. Writeback Logic (Data is Ready -> Tell ROB)
                // ------------------------------------
                // 這裡做一個簡單的輪詢：如果有 Valid Data 且還沒退休，就送 Writeback
                // 注意：這裡簡化了，實際硬體可能需要一個 FIFO 緩衝區來排隊 Writeback
                // 這裡我們優先 Writeback Head (為了簡單)，或者您可以掃描
                // 這裡修正為：Writeback Head if ready.
                
                // 如果您希望盡快 Writeback，可以在資料寫入的那一刻 (Forwarding 或 Cache Return) 直接觸發
                // 但為了配合你的介面 (wb_valid 是單脈衝)，我們檢測 Head 是否 Ready
                // **注意**：你的 wb_logic 原本是綁在 commit 上。
                // 如果你想保留「Commit 時才釋放」但「隨時可以 Writeback」：
                // 目前設計：當資料備妥時，這裡簡化為 "Commit 時順便 Writeback" (因為你的 Testbench 這樣測)
                // 但正確做法應該是分開。我這邊先依照你的 Testbench 邏輯保留 Commit 觸發釋放。
                
                // ------------------------------------
                // 6. Commit Logic (Free Entry)
                // ------------------------------------
                $display("[DEBUG-ALWAYS LOAD QUEUE] empty = %0b", empty);
                if(!empty) begin
                     if(lq[head].valid && rob_commit_valid && (rob_commit_valid_idx == lq[head].rob_idx)) begin
                        // 只有在 Commit 的時候才真正釋放 Entry
                        lq[head].valid <= 1'b0;
                        lq[head].data_valid <= 1'b0;
                        head <= next_ptr(head);
                        // count <= count - 1'b1;
                        
                        // 在 Commit 時送出 Writeback (配合你的 Testbench 預期)
                        $display("[DEBUG-ALWAYS LOAD QUEUE] lq[head].valid = %0b", lq[head].valid);
                        // if (lq[head].data_valid) begin
                        //     wb_valid <= 1'b1;
                        //     //  wb_rob_idx <= lq[head].rob_idx;
                        //     //  wb_data <= lq[head].data;
                        // end
                    end
                end

            end // else snapshot
        end // else reset
    end

    // Snapshot output connections
    generate 
        for (genvar i = 0 ; i < LQ_SIZE ; i++) begin
            // assign snapshot_data_o[i] = lq[i];
            assign snapshot_data_o[i].valid = lq[i].valid;
            assign snapshot_data_o[i].addr = lq[i].addr;
            assign snapshot_data_o[i].size = lq[i].size;
            assign snapshot_data_o[i].rob_idx = lq[i].rob_idx;
            assign snapshot_data_o[i].data_valid = lq[i].data_valid;
            assign snapshot_data_o[i].data = lq[i].data;
            assign snapshot_data_o[i].issued = lq[i].issued;
        end
    endgenerate
    assign snapshot_head_o = head;
    assign snapshot_tail_o = tail;
    assign snapshot_count_o = count;

endmodule