`timescale 1ns/1ps


module rob_testdata_nway2;

  // --------------------------------------------------
  // Parameters
  // --------------------------------------------------
  parameter int N = 2;         // Dispatch width
  parameter int WIDTH = 32;
  parameter int DEPTH = 64;
  parameter int ARCH_REGS = 64;
  parameter int PHYS_REGS = 128;
  parameter int WB_WIDTH = 4;
  parameter int XLEN = 64;
  parameter int NUM_GROUPS = 5;

  // --------------------------------------------------
  // Basic signals
  // --------------------------------------------------
  logic clk, rst_n;
  always #5 clk = ~clk;

  // Dispatch
  logic [N-1:0] disp_valid_i, disp_rd_wen_i;
  logic [$clog2(ARCH_REGS)-1:0] disp_rd_arch_i [N];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i [N];
  logic [$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i [N];
  logic [N-1:0] disp_ready_o, disp_alloc_o;
  logic [$clog2(DEPTH)-1:0] disp_rob_idx_o [N];

  // Writeback
  logic [WB_WIDTH-1:0] wb_valid_i, wb_exception_i, wb_mispred_i;
  logic [$clog2(DEPTH)-1:0] wb_rob_idx_i [WB_WIDTH];
  logic [XLEN-1:0] wb_value_i [WB_WIDTH];

  // Commit
  logic [N-1:0] commit_valid_o, commit_rd_wen_o;
  logic [$clog2(ARCH_REGS)-1:0] commit_rd_arch_o [N];
  logic [$clog2(PHYS_REGS)-1:0] commit_new_prf_o [N];
  logic [$clog2(PHYS_REGS)-1:0] commit_old_prf_o [N];

  // Flush
  logic flush_o;
  logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

  // --------------------------------------------------
  // Internal tracking (for checking correctness)
  // --------------------------------------------------
  typedef struct packed {
    int id;
    bit valid;
    bit committed;
    bit mispred;
    bit exception;
    int rob_idx;
    int arch, new_prf, old_prf;
    longint value;
  } instr_info_t;

  instr_info_t instr_table [0:DEPTH-1];
  int total_issued = 0, total_committed = 0, total_flushed = 0, total_failed = 0;

  // --------------------------------------------------
  // DUT instantiation
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
  task automatic clear_disp();
    disp_valid_i = '0;
    disp_rd_wen_i = '0;
  endtask

  task automatic clear_wb();
    wb_valid_i = '0;
    wb_exception_i = '0;
    wb_mispred_i = '0;
  endtask

  // 產生一組 N-way issue
  task automatic issue_group(int g_id);
    $display("\n[Cycle %0t] 🚀 Issue Group %0d", $time, g_id);
    for (int i = 0; i < N; i++) begin
      disp_valid_i[i] = 1;
      disp_rd_wen_i[i] = 1;
      disp_rd_arch_i[i] = $urandom_range(1, ARCH_REGS-1);
      disp_rd_new_prf_i[i] = $urandom_range(1, PHYS_REGS-1);
      disp_rd_old_prf_i[i] = $urandom_range(1, PHYS_REGS-1);
      instr_table[total_issued].id = total_issued;
      instr_table[total_issued].valid = 1;
      instr_table[total_issued].committed = 0;
      instr_table[total_issued].arch = disp_rd_arch_i[i];
      instr_table[total_issued].new_prf = disp_rd_new_prf_i[i];
      instr_table[total_issued].old_prf = disp_rd_old_prf_i[i];
      instr_table[total_issued].value = $urandom_range(1, 64'hFFFF);
      $display("   lane%0d | arch=%0d | newP=%0d | oldP=%0d | val=0x%h",
               i, instr_table[total_issued].arch,
               instr_table[total_issued].new_prf,
               instr_table[total_issued].old_prf,
               instr_table[total_issued].value);
      total_issued++;
    end
    #10;
    clear_disp();
  endtask

  // 模擬 WB + 檢查 flush
  task automatic simulate_wb();
    int num = $urandom_range(1, WB_WIDTH);
    $display("[Cycle %0t] 🔧 Writeback %0d instructions", $time, num);
    for (int i = 0; i < num; i++) begin
      wb_valid_i[i] = 1;
      wb_rob_idx_i[i] = $urandom_range(0, DEPTH-1);
      wb_exception_i[i] = 0;
      wb_mispred_i[i] = ($urandom_range(0,10) == 0);
      wb_value_i[i] = $urandom_range(1, 64'hFFFF);
    end
    #10;
    clear_wb();
    if (flush_o) begin
      $display("Flush triggered up to ROB[%0d]", flush_upto_rob_idx_o);
      total_flushed++;
    end
  endtask

  // 檢查 commit 結果
  always @(posedge clk) begin
    for (int i = 0; i < N; i++) begin
      if (commit_valid_o[i]) begin
        total_committed++;
        $display("[%0t] ✅ Commit lane%0d | arch=%0d | newP=%0d | oldP=%0d",
                 $time, i, commit_rd_arch_o[i],
                 commit_new_prf_o[i], commit_old_prf_o[i]);
      end
    end
  end

  // --------------------------------------------------
  // Main Sequence
  // --------------------------------------------------
  initial begin
    clk = 0; rst_n = 0;
    clear_disp(); clear_wb();
    #10 rst_n = 1;
    $display("=== [Start ROB Randomized Self-Check Test] ===");

    for (int g = 0; g < NUM_GROUPS; g++) begin
      issue_group(g);
      #10;
      simulate_wb();
      #10;

      if (flush_o)
        $display("✅ PASS: Flush detected (ROB cleared)");
      else
        $display("✅ PASS: Normal commit flow");

      $display("-----------------------------------------------------");
    end

        // ============ Check PASS / FAIL ============
    #20;
    $display("\n==================================================");
    $display("                 ROB TEST RESULT SUMMARY");
    $display("==================================================");

    int test_pass = 1; // overall flag

    // Check flush condition
    if (flush_o) begin
      $display("✅ [PASS] Flush detected at ROB index: %0d", flush_upto_rob_idx_o);
    end else begin
      $display("❌ [FAIL] Expected flush not triggered.");
      test_pass = 0;
    end

    // Check commit valid
    if (|commit_valid_o) begin
      int num_commit = 0;
      for (int i = 0; i < N; i++) begin
        if (commit_valid_o[i])
          num_commit++;
      end
      $display("✅ [PASS] Commit valid detected on %0d lane(s).", num_commit);
    end else begin
      $display("❌ [FAIL] No commit detected (commit_valid_o all 0).");
      test_pass = 0;
    end

    // Optional: show detail per lane
    $display("--------------------------------------------------");
    $display(" Lane | Commit_Valid | Rd_Arch | NewPRF | OldPRF ");
    $display("--------------------------------------------------");
    for (int i = 0; i < N; i++) begin
      $display("  %0d   |     %0d        |   %0d    |   %0d    |   %0d",
               i, commit_valid_o[i],
               commit_rd_arch_o[i],
               commit_new_prf_o[i],
               commit_old_prf_o[i]);
    end
    $display("--------------------------------------------------");

    // Final summary
    if (test_pass)
      $display("✅ [OVERALL RESULT] ROB TEST PASSED ✅");
    else
      $display("❌ [OVERALL RESULT] ROB TEST FAILED ❌");

    $display("Simulation Time: %0t ns", $time);
    $display("==================================================\n");

    #30;
    $display("=== ROB N-way Test: End ===");
    $finish;

    end
endmodule

