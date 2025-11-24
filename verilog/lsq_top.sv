`include "sys_defs.svh"

module lsq_top #(
    parameter int DISPATCH_WIDTH = 1,
    parameter int SQ_SIZE = 16,
    parameter int LQ_SIZE = 16,
    // 用於 snapshot 介面的計算
    parameter int SQ_IDX_WIDTH = $clog2(SQ_SIZE),
    parameter int LQ_IDX_WIDTH = $clog2(LQ_SIZE)
)(
    input logic clock, reset,

    // =====================================================
    // 1. Dispatch Stage (來自 Decode/Dispatch)
    // =====================================================
    input  logic       dispatch_valid,
    input  logic       dispatch_is_store, // 1=Store, 0=Load
    input  ADDR        dispatch_addr,
    input  MEM_SIZE    dispatch_size,
    input  ROB_IDX     dispatch_rob_idx,
    output logic       lsq_full,          // Stall signal to frontend

    // =====================================================
    // 2. Execution Stage (Store Data 來自 ALU/RegFile)
    // =====================================================
    input  logic       sq_data_valid,
    input  MEM_BLOCK   sq_data,
    input  ROB_IDX     sq_data_rob_idx,

    // =====================================================
    // 3. Commit Stage (來自 ROB)
    // =====================================================
    input  logic       commit_valid,
    input  ROB_IDX     commit_rob_idx, 

    // =====================================================
    // 4. Writeback Stage (Load 完成 -> CDB/ROB)
    // =====================================================
    output logic       wb_valid,
    output ROB_IDX     wb_rob_idx,
    output MEM_BLOCK   wb_data,

    // =====================================================
    // 5. Dual Port D-Cache Interface
    // =====================================================
    
    // --- Port 0: 用於 Load ---
    output ADDR        Dcache_addr_0,
    output MEM_COMMAND Dcache_command_0,   // MEM_LOAD / MEM_NONE
    output MEM_SIZE    Dcache_size_0,
    output MEM_BLOCK   Dcache_store_data_0, // 對 Load 來說無用，補 0
    input  logic       Dcache_req_0_accept, // Bank Conflict 處理
    
    input  MEM_BLOCK   Dcache_data_out_0,   // Load Data Return
    input  logic       Dcache_valid_out_0,  // Load Data Valid

    // --- Port 1: 用於 Store ---
    output ADDR        Dcache_addr_1,
    output MEM_COMMAND Dcache_command_1,   // MEM_STORE / MEM_NONE
    output MEM_SIZE    Dcache_size_1,
    output MEM_BLOCK   Dcache_store_data_1, // Store Data
    input  logic       Dcache_req_1_accept, // Bank Conflict 處理
    
    // Port 1 的回傳通常 Store 不用 (除非 atomic)，暫時忽略
    input  MEM_BLOCK   Dcache_data_out_1,   
    input  logic       Dcache_valid_out_1,

    // =====================================================
    // 6. Snapshot / Recovery Interface
    // =====================================================
    input logic [DISPATCH_WIDTH-1:0] is_branch_i,
    input logic                      snapshot_restore_valid_i,
    
    // SQ Snapshot
    output logic                     sq_checkpoint_valid_o,
    output sq_entry_t                sq_snapshot_data_o[SQ_SIZE-1:0],
    output logic [SQ_IDX_WIDTH-1:0]  sq_snapshot_head_o, sq_snapshot_tail_o,
    output logic [$clog2(SQ_SIZE+1)-1:0] sq_snapshot_count_o,
    input  sq_entry_t                sq_snapshot_data_i[SQ_SIZE-1:0],
    input  logic [SQ_IDX_WIDTH-1:0]  sq_snapshot_head_i, sq_snapshot_tail_i,
    input  logic [$clog2(SQ_SIZE+1)-1:0] sq_snapshot_count_i,

    // LQ Snapshot
    output logic                     lq_checkpoint_valid_o,
    output lq_entry_t                lq_snapshot_data_o[LQ_SIZE-1:0],
    output logic [LQ_IDX_WIDTH-1:0]  lq_snapshot_head_o, lq_snapshot_tail_o,
    output logic [$clog2(LQ_SIZE+1)-1:0] lq_snapshot_count_o,
    input  lq_entry_t                lq_snapshot_data_i[LQ_SIZE-1:0],
    input  logic [LQ_IDX_WIDTH-1:0]  lq_snapshot_head_i, lq_snapshot_tail_i,
    input  logic [$clog2(LQ_SIZE+1)-1:0] lq_snapshot_count_i
);

    // =====================================================
    // 內部訊號連接
    // =====================================================
    
    // Queue Full Status
    logic sq_full, lq_full;
    
    // Dispatch Steering
    logic sq_enq_valid;
    logic lq_enq_valid;

    // Forwarding Interface (LQ -> SQ -> LQ)
    ADDR        fwd_query_addr;   // LQ 問 SQ
    MEM_SIZE    fwd_query_size;   // LQ 問 SQ
    logic       fwd_valid;        // SQ 回覆 LQ
    MEM_BLOCK   fwd_data;         // SQ 回覆 LQ
    ADDR        fwd_res_addr;     // SQ 回覆 LQ (Addr match)
    logic       fwd_pending;      // SQ 回覆 LQ (Addr match but data not ready)

    // LQ Request Signals
    logic       lq_req_valid;
    ADDR        lq_req_addr;
    MEM_SIZE    lq_req_size;
    logic       lq_req_accept;

    // SQ Request Signals
    logic       sq_req_valid;
    ADDR        sq_req_addr;
    MEM_SIZE    sq_req_size;
    MEM_COMMAND sq_req_cmd;       // SQ 內部產生的 Command
    MEM_BLOCK   sq_req_data;
    logic       sq_req_accept;

    // =====================================================
    // Dispatch Steering Logic (分流)
    // =====================================================
    always_comb begin
        sq_enq_valid = 1'b0;
        lq_enq_valid = 1'b0;
        
        if (dispatch_valid) begin
            if (dispatch_is_store) begin
                sq_enq_valid = 1'b1;
            end else begin
                lq_enq_valid = 1'b1;
            end
        end
    end

    // 如果 dispatch Store 但 SQ 滿，或 dispatch Load 但 LQ 滿 -> Stall
    assign lsq_full = (dispatch_is_store && sq_full) || (!dispatch_is_store && lq_full);

    // =====================================================
    // Module Instances
    // =====================================================

    // 1. Store Queue Instance
    sq #(
        .DISPATCH_WIDTH(DISPATCH_WIDTH),
        .SQ_SIZE(SQ_SIZE)
    ) sq_inst (
        .clock(clock),
        .reset(reset),

        // Enqueue
        .enq_valid(sq_enq_valid),
        .enq_addr(dispatch_addr),
        .enq_size(dispatch_size),
        .enq_rob_idx(dispatch_rob_idx),
        .full(sq_full),

        // Data Update
        .data_valid(sq_data_valid),
        .data(sq_data),
        .data_rob_idx(sq_data_rob_idx),

        // Forwarding Logic (Service LQ query)
        .load_addr(fwd_query_addr),
        .load_size(fwd_query_size),
        .fwd_valid(fwd_valid),
        .fwd_data(fwd_data),
        .fwd_addr(fwd_res_addr),
        .fwd_pending(fwd_pending),

        // Commit
        .commit_valid(commit_valid),
        .commit_rob_idx(commit_rob_idx),

        // Output to D-Cache (Internal wires)
        .dc_req_valid(sq_req_valid),
        .dc_req_addr(sq_req_addr),
        .dc_req_size(sq_req_size),
        .dc_req_cmd(sq_req_cmd),
        .dc_store_data(sq_req_data), // 修正名稱對應
        .dc_req_accept(sq_req_accept),

        // Snapshot
        .is_branch_i(is_branch_i),
        .snapshot_restore_valid_i(snapshot_restore_valid_i),
        .checkpoint_valid_o(sq_checkpoint_valid_o),
        .snapshot_data_o(sq_snapshot_data_o),
        .snapshot_head_o(sq_snapshot_head_o),
        .snapshot_tail_o(sq_snapshot_tail_o),
        .snapshot_count_o(sq_snapshot_count_o),
        .snapshot_data_i(sq_snapshot_data_i),
        .snapshot_head_i(sq_snapshot_head_i),
        .snapshot_tail_i(sq_snapshot_tail_i),
        .snapshot_count_i(sq_snapshot_count_i)
    );

    // 2. Load Queue Instance
    lq #(
        .DISPATCH_WIDTH(DISPATCH_WIDTH),
        .LQ_SIZE(LQ_SIZE)
    ) lq_inst (
        .clock(clock),
        .reset(reset),

        // Enqueue
        .enq_valid(lq_enq_valid),
        .enq_addr(dispatch_addr),
        .enq_size(dispatch_size),
        .enq_rob_idx(dispatch_rob_idx),
        .full(lq_full),

        // Forwarding Logic (Ask SQ)
        .sq_forward_valid(fwd_valid),
        .sq_forward_data(fwd_data),
        .sq_forward_addr(fwd_res_addr),
        .sq_fwd_pending(fwd_pending),
        .sq_query_addr(fwd_query_addr),
        .sq_query_size(fwd_query_size),

        // Output to D-Cache (Internal wires)
        .dc_req_valid(lq_req_valid),
        .dc_req_addr(lq_req_addr),
        .dc_req_size(lq_req_size),
        .dc_req_accept(lq_req_accept),

        // Input from D-Cache
        .dc_load_data(Dcache_data_out_0),   // 連接 Port 0 回傳
        .dc_load_valid(Dcache_valid_out_0), // 連接 Port 0 Valid

        // Writeback / Commit
        .rob_commit_valid(commit_valid),
        .rob_commit_valid_idx(commit_rob_idx),
        .wb_valid(wb_valid),
        .wb_rob_idx(wb_rob_idx),
        .wb_data(wb_data),
        .empty(), 

        // Snapshot
        .is_branch_i(is_branch_i),
        .snapshot_restore_valid_i(snapshot_restore_valid_i),
        .checkpoint_valid_o(lq_checkpoint_valid_o),
        .snapshot_data_o(lq_snapshot_data_o),
        .snapshot_head_o(lq_snapshot_head_o),
        .snapshot_tail_o(lq_snapshot_tail_o),
        .snapshot_count_o(lq_snapshot_count_o),
        .snapshot_data_i(lq_snapshot_data_i),
        .snapshot_head_i(lq_snapshot_head_i),
        .snapshot_tail_i(lq_snapshot_tail_i),
        .snapshot_count_i(lq_snapshot_count_i)
    );

    // =====================================================
    // Cache Interface Connections (Dual Port Mappings)
    // =====================================================

    // -----------------------------------------------------
    // Port 0: LOAD Port (Connected to LQ)
    // -----------------------------------------------------
    // 當 LQ valid 時發送 MEM_LOAD，否則發送 MEM_NONE
    assign Dcache_command_0    = lq_req_valid ? MEM_LOAD : MEM_NONE;
    
    assign Dcache_addr_0       = lq_req_addr;
    assign Dcache_size_0       = lq_req_size;
    assign Dcache_store_data_0 = '0; // Load 不寫入資料
    
    // 將 Cache 的 Accept 回傳給 LQ
    assign lq_req_accept       = Dcache_req_0_accept;

    // -----------------------------------------------------
    // Port 1: STORE Port (Connected to SQ)
    // -----------------------------------------------------
    // 當 SQ valid 時發送 MEM_STORE (或其他 cmd)，否則發送 MEM_NONE
    assign Dcache_command_1    = sq_req_valid ? sq_req_cmd : MEM_NONE;
    
    assign Dcache_addr_1       = sq_req_addr;
    assign Dcache_size_1       = sq_req_size;
    assign Dcache_store_data_1 = sq_req_data;
    
    // 將 Cache 的 Accept 回傳給 SQ
    assign sq_req_accept       = Dcache_req_1_accept;

endmodule