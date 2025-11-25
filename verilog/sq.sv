`include "sys_defs.svh"

module sq #(
  parameter int DISPATCH_WIDTH = 1,
  parameter int SQ_SIZE = 16,
  parameter int IDX_WIDTH = $clog2(SQ_SIZE)
)(
    input logic clock, reset,

    // enqueue store addr
    input  logic       enq_valid,
    input  ADDR        enq_addr,
    input  MEM_SIZE    enq_size,
    input  ROB_IDX     enq_rob_idx,
    output logic       full,

    // later store data arrives
    input  logic       data_valid,
    input  MEM_BLOCK   data,
    input  ROB_IDX     data_rob_idx,

    // Forwarding query from LQ:
    // the LQ will present a load address/size; SQ responds combinationally
    input  ADDR        load_addr,
    input  MEM_SIZE    load_size,
    output logic       fwd_valid,
    output MEM_BLOCK   fwd_data,
    output ADDR        fwd_addr,
    output logic       fwd_pending,  // match exists but data not ready

    // commit from ROB
    input  logic       commit_valid,
    input  ROB_IDX     commit_rob_idx,

    // send store to dcache
    output logic       dc_req_valid,
    output ADDR        dc_req_addr,
    output MEM_SIZE    dc_req_size,
    output MEM_COMMAND dc_req_cmd,  // MEM_STORE
    output MEM_BLOCK   dc_store_data,   //need to solve this!!!
    input  logic       dc_req_accept,

    // =======================================================
    // ======== Snapshot / Flush control =====================
    // =======================================================

    input logic [DISPATCH_WIDTH-1:0] is_branch_i,
    // input logic                      flush_i,
    input logic                      snapshot_restore_valid_i, //valid bit
    output logic                     checkpoint_valid_o,
    output sq_entry_t                snapshot_data_o[SQ_SIZE-1:0],
    output logic   [IDX_WIDTH-1 : 0] snapshot_head_o , snapshot_tail_o,
    output logic   [$clog2(SQ_SIZE+1)-1:0] snapshot_count_o,
    input sq_entry_t                 snapshot_data_i[SQ_SIZE-1:0],
    input logic    [IDX_WIDTH-1 : 0] snapshot_head_i , snapshot_tail_i,
    input logic   [$clog2(SQ_SIZE+1)-1:0] snapshot_count_i

);
  // typedef struct packed {
  //   logic     valid;
  //   ADDR      addr;
  //   MEM_SIZE  size;
  //   ROB_IDX   rob_idx;
  //   logic     data_valid;
  //   MEM_BLOCK data;
  //   logic     commited; 
  // } sq_entry_t; // marked by ROB commited

  sq_entry_t sq[SQ_SIZE];
  logic [IDX_WIDTH-1 : 0]head,tail;
  logic [$clog2(SQ_SIZE+1)-1:0] count;


  // -----------------------------------------
    // Circular increment function 
    // -----------------------------------------
    function automatic [IDX_WIDTH-1:0] next_ptr(input [IDX_WIDTH-1:0] ptr);
        if (ptr == SQ_SIZE-1)
            return 0;
        else
            return ptr + 1;
    endfunction

  // forwarding logic
  function automatic logic addr_overlap(ADDR store_addr , MEM_SIZE store_size , ADDR load_addr , MEM_SIZE load_size);
    int byte_store , byte_load;
    begin
      case (store_size)
        BYTE:byte_store = 1;
        HALF:byte_store = 2;
        WORD:byte_store = 4;
        DOUBLE:byte_store = 8;
        default: byte_store = 4;
      endcase
      case (load_size)
        BYTE:byte_load = 1;
        HALF:byte_load = 2;
        WORD:byte_load = 4;
        DOUBLE:byte_load = 8;
        default:byte_load = 4;
      endcase
      addr_overlap = !((store_addr + byte_store - 1) < load_addr || (load_addr + byte_load - 1) < store_addr);
    end
  endfunction

    //### 11/10 sychenn ###//
    logic checkpoint_valid_next;
    always_comb begin 
        checkpoint_valid_next = 1'b0;
        for(int i =0 ; i < DISPATCH_WIDTH ; i++)begin
            if(is_branch_i[i])begin
                checkpoint_valid_next = 1'b1;
                break;
            end
        end        
    end

    assign full = (count == SQ_SIZE);
    // dc request generation for head
    // assign dc_req_valid = (sq[head].valid && sq[head].committed && sq[head].data_valid);
    // assign dc_req_addr  = sq[head].addr;
    // assign dc_req_size  = sq[head].size;
    // assign dc_req_cmd   = MEM_STORE;
    // assign dc_req_data  = sq[head].data;


  always_ff @(posedge clock)begin
    if(reset)begin
      head <= '0;
      tail <= '0;
      count <= '0;
      checkpoint_valid_o <= 1'b0;
      for(int i = 0 ; i < SQ_SIZE ; i++)begin
        sq[i].valid <= '0;
        sq[i].addr <= '0;
        sq[i].size <= '0;
        sq[i].rob_idx <= '0;
        sq[i].data_valid <= '0;
        sq[i].data <= '0;
        sq[i].commited <= '0;
      end
    end else begin 
      checkpoint_valid_o <= checkpoint_valid_next;
      if (snapshot_restore_valid_i) begin
        head <= snapshot_head_i;
        tail <= snapshot_tail_i;
        count <= snapshot_count_i;
        for(int i =0 ; i < SQ_SIZE ; i++)begin
          sq[i].valid <= snapshot_data_i[i].valid;
          sq[i].addr <= snapshot_data_i[i].addr;
          sq[i].size <= snapshot_data_i[i].size;
          sq[i].rob_idx <= snapshot_data_i[i].rob_idx;
          sq[i].data_valid <= snapshot_data_i[i].data_valid;
          sq[i].data <= snapshot_data_i[i].data;
          sq[i].commited <= snapshot_data_i[i].commited;
        end
      end
      else begin
        if (enq_valid && !full)begin
          // $display("[RTL-SQ] Enqueue at tail=%0d, ROB=%0d, Addr=%h", tail, enq_rob_idx, enq_addr);
          sq[tail].valid <= 1'b1;
          sq[tail].addr <= enq_addr;
          sq[tail].size <= enq_size;
          sq[tail].data_valid <= 1'b0;
          sq[tail].commited <= 1'b0;
          sq[tail].rob_idx <= enq_rob_idx;
          // tail <= tail + 1'b1;
          tail <= next_ptr(tail);
          count <= count + 1'b1; 
        end 

        // store data arrived(match by rob_idx)
        if (data_valid)begin
          // $display("[RTL-SQ] Update Data Request for ROB=%0d, Data=%h", data_rob_idx, data);
          for(int i = 0 ; i < SQ_SIZE ; i++)begin // simple linear search
            $display("   Checking idx=%0d: Valid=%b, ROB=%0d", i, sq[i].valid, sq[i].rob_idx);
            if(sq[i].valid && (sq[i].rob_idx == data_rob_idx))begin
              // $display("[RTL-SQ]   -> MATCH FOUND at idx=%0d! Updating Data.", i);
              sq[i].data <= data;
              sq[i].data_valid <= 1'b1;
              break;
            end 
          end
        end 

        // // commit notification from ROB
        // if (commit_valid)begin
        //   for(int i =0 ; i< SQ_SIZE ; i++)begin
        //     if(sq[i].data_valid && sq[i].valid && (sq[i].rob_idx == commit_rob_idx))begin
        //       sq[i].commited <= 1'b1;
        //       // dc_req_valid <= 1'b1;
        //       break;
        //     end
        //   end
        // end

        //commit from ROB: mark matching store as commited (so it can be sent when head)
        if(commit_valid)begin
          for(int i = 0 ; i < SQ_SIZE ; i++)begin
            if(sq[i].valid && sq[i].data_valid && (sq[i].rob_idx == commit_rob_idx))begin
              sq[i].commited <= 1'b1;
              // dc_store_data <= sq[i].data;
              break;
            end
          end
        end 
      

        // if head is ready to send to dcache (committed && data_valid) and we get accept -> pop
        if(dc_req_valid && dc_req_accept)begin
          sq[head].valid <= 1'b0;
          sq[head].data_valid <= 1'b0;
          sq[head].commited <= 1'b0;
          count <= count - 1'b1;
          head <= next_ptr(head);
        end
      end
    end
  end


  logic found, pending_found;
  MEM_BLOCK found_data;
  ADDR found_addr;

  always_comb begin
    int k;
    int i;
    int start;
    found = 1'b0;
    pending_found = 1'b0;
    found_data = '0;
    found_addr = '0;
    $display("[DEBUG-ALWAYS STORE QUEUE] Count=%0d, Tail=%0d, Head=%0d", count, tail, head);
    if(count != 0)begin
      int checked = 0;
      // start at tail - 1 (most recent store) and go backwards up to count entries
      start  = (tail==0) ? (SQ_SIZE - 1) : (tail - 1);
      // idx = tail - 1;
      for(k = 0 ; k < SQ_SIZE ; k++)begin
        // int i = (idx - k) % SQ_SIZE;
        i = start - k;
        if(i<0)i = i + SQ_SIZE;
        // $display("[DEBUG-FWD] Checking indx = %0d, sq[%0d] = %0d , k=%0d , start = %0d" , i , i , sq[i].valid , k , start);
        if(sq[i].valid)begin
          $display("[DEBUG-FWD] Checking idx=%0d. SQ_Addr=%h, SQ_Size=%0d | Load_Addr=%h, Load_Size=%0d", 
                   i, sq[i].addr, sq[i].size, load_addr, load_size);
          if(addr_overlap(sq[i].addr , sq[i].size , load_addr , load_size))begin
            $display("[RTL-SQ-FWD] Overlap at idx=%0d. DataValid=%b. Data=%h", i, sq[i].data_valid, sq[i].data);
            if(sq[i].data_valid)begin
              found = 1'b1;
              pending_found = 1'b0;
              found_data = sq[i].data;
              found_addr = sq[i].addr;
              // $display("[RTL-SQ-FWD]found = %0b , ")
              break;
            end else begin
              $display("[DEBUG-ALWAYS] Loop idx=%0d has Valid=0! (This is wrong)", i);
              pending_found = 1'b1;break;
            end
          end
        end
        checked++;
        if(checked >= count)break;
      end
    end
  end

  assign fwd_valid = found;
  assign fwd_data = found_data;
  assign fwd_addr = found_addr;
  assign fwd_pending = pending_found;

  // ---------------------------------------------------------
  // Decide DC request for head (combinational)
  // We only send store to D$ when head is valid & committed & data_valid
  // (this is a combinational request; acceptance handled below)
  // ---------------------------------------------------------
  logic dc_req_req;
  always_comb begin
    dc_req_req = 1'b0;
    dc_req_addr = '0;
    dc_req_size = '0;
    dc_store_data = '0;
    if (count != 0) begin
      if (sq[head].valid && sq[head].commited && sq[head].data_valid) begin
        dc_req_req = 1'b1;
        dc_req_addr = sq[head].addr;
        dc_req_size = sq[head].size;
        dc_store_data = sq[head].data;
      end
    end
  end
  assign dc_req_valid = dc_req_req;
  assign dc_req_cmd   = MEM_STORE;


// =======================================================
    // Snapshot output: provide current mapping (for ROB/CPU to save)
    // Drive it continuously from table_reg; CPU will latch on checkpoint_valid_o
    // =======================================================
  generate 
      for (genvar i = 0 ; i < SQ_SIZE ; i++)begin
          assign snapshot_data_o[i].valid = sq[i].valid;
          assign snapshot_data_o[i].addr = sq[i].addr;
          assign snapshot_data_o[i].size = sq[i].size;
          assign snapshot_data_o[i].rob_idx = sq[i].rob_idx;
          assign snapshot_data_o[i].data_valid = sq[i].data_valid;
          assign snapshot_data_o[i].data = sq[i].data;
          assign snapshot_data_o[i].commited = sq[i].commited;
      end
  endgenerate
  assign snapshot_head_o = head;
  assign snapshot_tail_o = tail;
  assign snapshot_count_o = count;
    // =======================================================
    // =======================================================
    // =======================================================
    // =======================================================



endmodule