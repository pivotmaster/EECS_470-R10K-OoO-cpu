`timescale 1ns/1ps

// =====================================================
// EECS 470 – Team 14: Ron Fisher
// ROB Test Data (N-way with Value, Valid, and Pass/Fail)
// Author: Tzu Hsuan Lee
// =====================================================

module rob_testdata_nway;

  // --------------------------------------------------
  // Parameters
  // --------------------------------------------------
  localparam int N = 2;                // N-way superscalar issue
  localparam int DEPTH = 64;
  localparam int ARCH_REGS = 64;
  localparam int PHYS_REGS = 128;
  localparam int WB_WIDTH = 4;
  localparam int XLEN = 64;

  // --------------------------------------------------
  // Clock / Reset
  // --------------------------------------------------
  logic clk, rst_n;
  always #5 clk = ~clk;

  // --------------------------------------------------
  // Dispatch Interface
  // --------------------------------------------------
  logic [N-1:0] disp_valid_i, disp_rd_wen_i;
  logic [$clog2(ARCH_REGS)-1:0] disp_rd_arch_i [N];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i [N];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i [N];
  logic [N-1:0] disp_ready_o, disp_alloc_o;
  logic [$clog2(DEPTH)-1:0] disp_rob_idx_o [N];

  // --------------------------------------------------
  // Writeback + Commit + Flush
  // --------------------------------------------------
  logic [WB_WIDTH-1:0] wb_valid_i, wb_exception_i, wb_mispred_i;
  logic [$clog2(DEPTH)-1:0] wb_rob_idx_i [WB_WIDTH];
  logic [XLEN-1:0] wb_value_i [WB_WIDTH];   // 新增：模擬寫回的值

  logic [N-1:0] commit_valid_o, commit_rd_wen_o;
  logic [$clog2(ARCH_REGS)-1:0] commit_rd_arch_o [N];
  logic [$clog2(PHYS_REGS)-1:0] commit_new_prf_o [N];
  logic [$clog2(PHYS_REGS)-1:0] commit_old_prf_o [N];
  logic [XLEN-1:0] commit_value_o [N];      // 模擬 ROB commit 值（假設有此欄位）

  logic flush_o;
  logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

  // --------------------------------------------------
  // DUT instance
  // --------------------------------------------------
  ROB #(
    .DEPTH(DEPTH),
    .INST_W(16),
    .DISPATCH_WIDTH(N),
    .COMMIT_WIDTH(N),
    .WB_WIDTH(WB_WIDTH),
    .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS),
    .XLEN(XLEN)
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

  // --------------------------------------------------
  // Utility Tasks
  // --------------------------------------------------
  task automatic clear_dispatch();
    disp_valid_i = '0;
    disp_rd_wen_i = '0;
  endtask

  task automatic clear_wb();
    wb_valid_i = '0;
    wb_exception_i = '0;
    wb_mispred_i = '0;
  endtask

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  // --------------------------------------------------
  // Monitor + Display Logic
  // --------------------------------------------------
  always @(posedge clk) begin
    if (flush_o)
      $display("[%0t] 🔁 FLUSH TRIGGERED up to ROB[%0d]", $time, flush_upto_rob_idx_o);

    for (int i = 0; i < N; i++) begin
      if (commit_valid_o[i]) begin
        $display("[%0t] ✅ COMMIT lane%0d → arch=%0d, newP=%0d, oldP=%0d, value=0x%h",
                 $time, i, commit_rd_arch_o[i],
                 commit_new_prf_o[i], commit_old_prf_o[i],
                 commit_value_o[i]);
      end
    end
  end

  // --------------------------------------------------
  // Test Sequence
  // --------------------------------------------------
  initial begin
    clk = 0; rst_n = 0;
    clear_dispatch();
    clear_wb();
    #10 rst_n = 1;
    $display("=== ROB N-way Test: Start ===");

    // ============ Dispatch ============
    // Cycle 1
    disp_valid_i = 2'b11;
    disp_rd_wen_i = 2'b11;
    disp_rd_arch_i[0] = 3; disp_rd_new_prf_i[0] = 8; disp_rd_old_prf_i[0] = 3;
    disp_rd_arch_i[1] = 4; disp_rd_new_prf_i[1] = 9; disp_rd_old_prf_i[1] = 4;
    step(); clear_dispatch();
    $display("[Cycle 1] 🚀 Issued I0, I1");

    // Cycle 2
    disp_valid_i = 2'b11;
    disp_rd_wen_i = 2'b11;
    disp_rd_arch_i[0] = 1; disp_rd_new_prf_i[0] = 10; disp_rd_old_prf_i[0] = 1;
    disp_rd_arch_i[1] = 2; disp_rd_new_prf_i[1] = 11; disp_rd_old_prf_i[1] = 2;
    step(); clear_dispatch();
    $display("[Cycle 2] 🚀 Issued I2, I3");

    // ============ Writeback ============
    #10;
    wb_valid_i = 4'b0011;
    wb_rob_idx_i[0] = 0; wb_value_i[0] = 64'h1111_1111_1111_0000;
    wb_rob_idx_i[1] = 1; wb_value_i[1] = 64'h2222_2222_2222_0000;
    step(); clear_wb();
    $display("[WB] I0, I1 completed with values 0x1111..., 0x2222...");

    // Simulate mispredict flush
    #10;
    wb_valid_i = 4'b0001;
    wb_rob_idx_i[0] = 2;
    wb_mispred_i = 4'b0001;
    wb_value_i[0] = 64'hDEAD_BEEF_1234_0000;
    step(); clear_wb();
    $display("[WB] I2 mispredicted → expect FLUSH");

    // ============ Check PASS / FAIL ============
    #20;
    if (flush_o)
      $display("✅ TEST PASS: Flush triggered at ROB[%0d]", flush_upto_rob_idx_o);
    else
      $display("❌ TEST FAIL: Expected flush not triggered");

    if (|commit_valid_o)
      $display("✅ COMMIT VALID detected");
    else
      $display("❌ TEST FAIL: No commit detected");

    #50;
    $display("=== ROB N-way Test: End ===");
    $finish;
  end
endmodule
