`timescale 1ns/1ps

module rob_testdata_nway;

  // ==========
  // Parameters
  // ==========
  localparam int N = 2;   // N-way 發射寬度
  localparam int DEPTH = 64;
  localparam int ARCH_REGS = 64;
  localparam int PHYS_REGS = 128;

  // ==========
  // Clock / Reset
  // ==========
  logic clk, rst_n;
  always #5 clk = ~clk;

  // ==========
  // Dispatch signals
  // ==========
  logic [N-1:0] disp_valid_i;
  logic [N-1:0] disp_rd_wen_i;
  logic [$clog2(ARCH_REGS)-1:0] disp_rd_arch_i [N];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i [N];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i [N];

  logic [N-1:0] disp_ready_o;
  logic [N-1:0] disp_alloc_o;
  logic [$clog2(DEPTH)-1:0] disp_rob_idx_o [N];

  // ==========
  // Writeback / Commit / Flush
  // ==========
  logic [3:0] wb_valid_i, wb_exception_i, wb_mispred_i;
  logic [$clog2(DEPTH)-1:0] wb_rob_idx_i [4];

  logic [N-1:0] commit_valid_o, commit_rd_wen_o;
  logic [$clog2(ARCH_REGS)-1:0] commit_rd_arch_o [N];
  logic [$clog2(PHYS_REGS)-1:0] commit_new_prf_o [N];
  logic [$clog2(PHYS_REGS)-1:0] commit_old_prf_o [N];

  logic flush_o;
  logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

  // ==========
  // DUT instance
  // ==========
  ROB #(
    .DEPTH(DEPTH),
    .DISPATCH_WIDTH(N),
    .COMMIT_WIDTH(N),
    .WB_WIDTH(4),
    .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .disp_valid_i(disp_valid_i),
    .disp_rd_wen_i(disp_rd_wen_i),
    .disp_rd_arch_i(disp_rd_arch_i),
    .disp_rd_new_prf_i(disp_rd_new_prf_i),
    .disp_rd_old_prf_i(disp_rd_old_prf_i),
    .disp_ready_o(disp_ready_o),
    .disp_alloc_o(disp_alloc_o),
    .disp_rob_idx_o(disp_rob_idx_o),
    .wb_valid_i(wb_valid_i),
    .wb_rob_idx_i(wb_rob_idx_i),
    .wb_exception_i(wb_exception_i),
    .wb_mispred_i(wb_mispred_i),
    .commit_valid_o(commit_valid_o),
    .commit_rd_wen_o(commit_rd_wen_o),
    .commit_rd_arch_o(commit_rd_arch_o),
    .commit_new_prf_o(commit_new_prf_o),
    .commit_old_prf_o(commit_old_prf_o),
    .flush_o(flush_o),
    .flush_upto_rob_idx_o(flush_upto_rob_idx_o)
  );

  // ==========
  // Stimulus (test data)
  // ==========
  initial begin
    clk = 0; rst_n = 0;
    disp_valid_i = '0; wb_valid_i = '0;
    #10 rst_n = 1;
    $display("=== Start ROB N-way Test ===");

    // Cycle 1: issue two instructions
    disp_valid_i = 2'b11;
    disp_rd_wen_i = 2'b11;
    disp_rd_arch_i[0] = 3;  disp_rd_new_prf_i[0] = 8;  disp_rd_old_prf_i[0] = 3;
    disp_rd_arch_i[1] = 4;  disp_rd_new_prf_i[1] = 9;  disp_rd_old_prf_i[1] = 4;
    #10 disp_valid_i = '0;

    // Cycle 2: issue next two instructions
    disp_valid_i = 2'b11;
    disp_rd_arch_i[0] = 1;  disp_rd_new_prf_i[0] = 10; disp_rd_old_prf_i[0] = 1;
    disp_rd_arch_i[1] = 2;  disp_rd_new_prf_i[1] = 11; disp_rd_old_prf_i[1] = 2;
    #10 disp_valid_i = '0;

    // Simulate WB of first few ROB entries
    #20;
    wb_valid_i = 4'b0011;
    wb_rob_idx_i[0] = 0; // writeback entry 0
    wb_rob_idx_i[1] = 1; // writeback entry 1
    #10 wb_valid_i = '0;

    // Trigger a mispredict (flush)
    #10;
    wb_valid_i = 4'b0001;
    wb_mispred_i = 4'b0001;
    wb_rob_idx_i[0] = 2;
    #10 wb_valid_i = '0; wb_mispred_i = '0;

    #50;
    $display("=== End ROB N-way Test ===");
    $finish;
  end
endmodule
