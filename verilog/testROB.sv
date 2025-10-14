`timescale 1ns/1ps

module tb_rob_only;

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
  logic clk, rst_n;

  // DUT I/O
  logic [DISPATCH_WIDTH-1:0] disp_valid_i, disp_rd_wen_i;
  logic [$clog2(ARCH_REGS)-1:0] disp_rd_arch_i [DISPATCH_WIDTH];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i [DISPATCH_WIDTH];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i [DISPATCH_WIDTH];
  logic [DISPATCH_WIDTH-1:0] disp_ready_o, disp_alloc_o;
  logic [$clog2(DEPTH)-1:0] disp_rob_idx_o [DISPATCH_WIDTH];

  logic [WB_WIDTH-1:0] wb_valid_i, wb_exception_i, wb_mispred_i;
  logic [$clog2(DEPTH)-1:0] wb_rob_idx_i [WB_WIDTH];

  logic [COMMIT_WIDTH-1:0] commit_valid_o, commit_rd_wen_o;
  logic [$clog2(ARCH_REGS)-1:0] commit_rd_arch_o [COMMIT_WIDTH];
  logic [$clog2(PHYS_REGS)-1:0] commit_new_prf_o [COMMIT_WIDTH];
  logic [$clog2(PHYS_REGS)-1:0] commit_old_prf_o [COMMIT_WIDTH];

  logic flush_o;
  logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

  // Instantiate ROB
  ROB #(
    .DEPTH(DEPTH), .INST_W(INST_W),
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .COMMIT_WIDTH(COMMIT_WIDTH),
    .WB_WIDTH(WB_WIDTH), .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS), .XLEN(XLEN)
  ) dut (
    .clk(clk), .rst_n(rst_n),
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
    clk = 0; rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // Stimulus: dispatch → writeback → commit
  initial begin
    // init
    disp_valid_i = '0; disp_rd_wen_i = '0;
    wb_valid_i   = '0; wb_exception_i = '0; wb_mispred_i = '0;

    @(posedge rst_n);

    // Dispatch one instruction
    @(posedge clk);
    disp_valid_i[0]     = 1;
    disp_rd_wen_i[0]    = 1;
    disp_rd_arch_i[0]   = 5'd1;
    disp_rd_new_prf_i[0]= 7'd10;
    disp_rd_old_prf_i[0]= 7'd2;

    @(posedge clk);
    disp_valid_i = '0;

    // Writeback that instruction
    @(posedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = disp_rob_idx_o[0];

    @(posedge clk);
    wb_valid_i = '0;

    // Observe commit
    repeat (5) @(posedge clk);

    $finish;
  end

  // Monitor
  always @(posedge clk) begin
    if (commit_valid_o[0])
      $display("[%0t] Commit: arch=%0d new=%0d old=%0d",
               $time, commit_rd_arch_o[0],
               commit_new_prf_o[0], commit_old_prf_o[0]);
    if (flush_o)
      $display("[%0t] Flush up to ROB idx %0d", $time, flush_upto_rob_idx_o);
  end

endmodule
