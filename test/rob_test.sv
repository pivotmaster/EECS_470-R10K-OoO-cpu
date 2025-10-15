`timescale 1ns/1ps

module tb_rob_only;

  logic start_sim;

  // Parameters match ROB
  localparam int DEPTH          = 64;
  localparam int INST_W         = 16;
  localparam int DISPATCH_WIDTH = 2;
  localparam int COMMIT_WIDTH   = 2;
  localparam int WB_WIDTH       = 4;
  localparam int ARCH_REGS      = 64;
  localparam int PHYS_REGS      = 128;
  localparam int XLEN           = 64;

  // Clock/reset
  logic clk, reset;

  // DUT I/O
  logic [DISPATCH_WIDTH-1:0] disp_valid_i, disp_rd_wen_i;
  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] disp_rd_arch_i;
  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i;
  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i;
  logic [DISPATCH_WIDTH-1:0] disp_ready_o, disp_alloc_o;
  logic [DISPATCH_WIDTH-1:0][$clog2(DEPTH)-1:0] disp_rob_idx_o;

  logic [WB_WIDTH-1:0] wb_valid_i, wb_exception_i, wb_mispred_i;
  logic [WB_WIDTH-1:0][$clog2(DEPTH)-1:0] wb_rob_idx_i;

  logic [COMMIT_WIDTH-1:0] commit_valid_o, commit_rd_wen_o;
  logic [COMMIT_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] commit_rd_arch_o;
  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] commit_new_prf_o;
  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] commit_old_prf_o;

  logic flush_o;
  logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

  // Instantiate ROB
  rob #(
    .DEPTH(DEPTH), .INST_W(INST_W),
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .COMMIT_WIDTH(COMMIT_WIDTH),
    .WB_WIDTH(WB_WIDTH), .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS), .XLEN(XLEN)
  ) dut (
    .clk(clk), .reset(reset),
    .disp_valid_i(disp_valid_i), .disp_rd_wen_i(disp_rd_wen_i),
    .disp_rd_arch_i(disp_rd_arch_i),
    .disp_rd_new_prf_i(disp_rd_new_prf_i),
    .disp_rd_old_prf_i(disp_rd_old_prf_i),
    .disp_ready_o(disp_ready_o), .disp_alloc_o(disp_alloc_o),
    .disp_rob_idx_o(disp_rob_idx_o),
    .wb_valid_i(wb_valid_i), .wb_rob_idx_i(wb_rob_idx_i),
    .wb_exception_i(wb_exception_i), .wb_mispred_i(wb_mispred_i),
    .commit_valid_o(commit_valid_o), .commit_rd_wen_o(commit_rd_wen_o),
    .commit_rd_arch_o(commit_rd_arch_o),
    .commit_new_prf_o(commit_new_prf_o),
    .commit_old_prf_o(commit_old_prf_o),
    .flush_o(flush_o), .flush_upto_rob_idx_o(flush_upto_rob_idx_o)
  );

  // Clock
  always #5 clk = ~clk;

  // Reset
  initial begin
    clk = 0; reset = 1;
    repeat (3) @(negedge clk);
    reset = 0;
  end
  
  // Stimulus: multiple dispatch/writeback/flush tests
  int total_dispatched, prf_counter, ridx;
  initial begin
    // === init ===
    start_sim = 0;
    disp_valid_i = '0; disp_rd_wen_i = '0;
    wb_valid_i   = '0; wb_exception_i = '0; wb_mispred_i = '0;

    @(negedge reset);
    @(negedge clk); // wait reset end

    
     // =====================================================
    // [Phase 1] Dispatch a ins -> commit
    // =====================================================
    $display("\n=== Phase 1: Single Dispatch/Commit ===");
    start_sim = 1;
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd1;
    disp_rd_new_prf_i[0] = 7'd10;
    disp_rd_old_prf_i[0] = 7'd2;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback (ROB idx 0)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 0;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 2] dispatch two ways, writeback one way
    // =====================================================
    $display("\n=== Phase 2: Dual Dispatch, Staggered WB ===");
    @(negedge clk);
    disp_valid_i      = 2'b11;
    disp_rd_wen_i     = 2'b11;
    disp_rd_arch_i[0] = 5'd3;  disp_rd_new_prf_i[0] = 7'd11;  disp_rd_old_prf_i[0] = 7'd5;
    disp_rd_arch_i[1] = 5'd4;  disp_rd_new_prf_i[1] = 7'd12;  disp_rd_old_prf_i[1] = 7'd6;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback second（ROB idx 1）
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 2;

    @(negedge clk);
    wb_valid_i = '0;

    // writeback first（ROB idx 2）
    repeat (3) @(negedge clk);
    wb_valid_i[1]   = 1;
    wb_rob_idx_i[1] = 1;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (6) @(negedge clk);

    // =====================================================
    // [Phase 3] test mispredict -> flush
    // =====================================================
    $display("\n=== Phase 3: Mispredict Flush Test ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd7;
    disp_rd_new_prf_i[0] = 7'd13;
    disp_rd_old_prf_i[0] = 7'd8;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback, mispred (ROB idx 3)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 3;
    wb_mispred_i[0] = 1;  // flush

    @(negedge clk);
    wb_valid_i = '0; wb_mispred_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 4] dispatch after flush
    // =====================================================
    $display("\n=== Phase 4: Post-Flush Dispatch ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd9;
    disp_rd_new_prf_i[0] = 7'd14;
    disp_rd_old_prf_i[0] = 7'd4;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback + Commit (ROB idx 4)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 4;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 5] Commit two ins at the same time
    // =====================================================
    $display("\n=== Phase 5: test Commit two ins at the same time ===");

    @(negedge clk);
    // Dispatch
    disp_valid_i      = 2'b11;
    disp_rd_wen_i     = 2'b11;
    disp_rd_arch_i[0] = 5'd10; disp_rd_new_prf_i[0] = 7'd15; disp_rd_old_prf_i[0] = 7'd3;
    disp_rd_arch_i[1] = 5'd11; disp_rd_new_prf_i[1] = 7'd16; disp_rd_old_prf_i[1] = 7'd4;
    @(negedge clk);
    disp_valid_i = '0;

    // writeback two ins
    @(negedge clk);
    wb_valid_i = 4'b0011;
    wb_rob_idx_i[0] = 5;
    wb_rob_idx_i[1] = 6;
    @(negedge clk);
    
    wb_valid_i = '0;
    @(negedge clk);
    // =====================================================
    // [Phase 6] Dispatch until ROB is full
    // =====================================================
    $display("\n=== Phase 6: Dispatch until ROB is full ===");
    total_dispatched = 0;
    prf_counter = 20;
    while(total_dispatched < 100) begin
      @(negedge clk);
      for (int i = 0; i < DISPATCH_WIDTH; i++) begin
        disp_valid_i[i]      = 1;
        disp_rd_wen_i[i]     = 1;
        disp_rd_arch_i[i]    = (total_dispatched + 12) % ARCH_REGS;
        disp_rd_new_prf_i[i] = prf_counter + 10;
        disp_rd_old_prf_i[i] = prf_counter;
        total_dispatched++;
        prf_counter++;
        // $display("dispatch 2");
      end
    end
    disp_valid_i = 0;
    @(negedge clk);
    // =====================================================
    // [Phase 7] WB from back
    // =====================================================
    $display("\n=== Phase 7: WB from back ===");
    for (ridx = DEPTH-1; ridx >= 0; ridx--) begin
      @(negedge clk);
      wb_valid_i      = 4'b0011;
      wb_rob_idx_i[0] = ridx;
      if(ridx == DEPTH - 11) begin
        wb_mispred_i[0] = 1;
        $display("%0d is mispred", ridx);
      end else begin
        wb_mispred_i[0] = 0;
      end
      wb_rob_idx_i[1] = (ridx > 0) ? ridx-1 : ridx;
      $display("[%0t] WB two entries: ROB[%0d] and ROB[%0d]", 
               $time, wb_rob_idx_i[0], wb_rob_idx_i[1]);
      ridx--;
    end

    @(negedge clk);
    wb_valid_i = '0;
    $display("\n=== Phase 7 Complete: Reverse writeback finished ===");

    repeat (40) @(negedge clk);

    repeat (8) @(negedge clk);

    $display("\n=== Simulation Finished ===");
    $finish;
  end

  always @(negedge clk) begin
    if(start_sim) begin
      for(int i = 0; i < COMMIT_WIDTH; i++) begin
        if (commit_valid_o[i])
          $display("[%0t] Commit %0d: arch=%0d new=%0d old=%0d",
                  $time, i, commit_rd_arch_o[i],
                  commit_new_prf_o[i], commit_old_prf_o[i]);
      end
      if (|commit_valid_o)
        $display("commit num: %0d", $countones(commit_valid_o));
      if (flush_o)
        $display("[%0t] Flush up to ROB idx %0d", $time, flush_upto_rob_idx_o);
    end
  end

endmodule
