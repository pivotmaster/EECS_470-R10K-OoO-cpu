`timescale 1ns/1ps

module tb_rob_nway;  // testdata2

// ================================
// Parameters match ROB
// ================================
localparam int DEPTH          = 64;
localparam int INST_W         = 16;
localparam int DISPATCH_WIDTH = 2;
localparam int COMMIT_WIDTH   = 2;
localparam int WB_WIDTH       = 4;
localparam int ARCH_REGS      = 64;
localparam int PHYS_REGS      = 128;
localparam int XLEN           = 64;

// ================================
// Clock/reset
// ================================
logic clk, reset;
always #5 clk = ~clk; // 每 5ns 反轉時鐘

// ================================
// DUT I/O
// ================================
logic [DISPATCH_WIDTH-1:0] disp_valid_i, disp_rd_wen_i;
logic [$clog2(ARCH_REGS)-1:0] disp_rd_arch_i [DISPATCH_WIDTH];
logic [$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i [DISPATCH_WIDTH];
logic [$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i [DISPATCH_WIDTH];
logic [DISPATCH_WIDTH-1:0] disp_ready_o, disp_alloc_o;
logic [$clog2(DEPTH)-1:0] disp_rob_idx_o [DISPATCH_WIDTH];

logic [WB_WIDTH-1:0] wb_valid_i, wb_exception_i, wb_mispred_i;
logic [$clog2(DEPTH)-1:0] wb_rob_idx_i [WB_WIDTH];
logic [XLEN-1:0] wb_value_i [WB_WIDTH];

logic [COMMIT_WIDTH-1:0] commit_valid_o, commit_rd_wen_o;
logic [$clog2(ARCH_REGS)-1:0] commit_rd_arch_o [COMMIT_WIDTH];
logic [$clog2(PHYS_REGS)-1:0] commit_new_prf_o [COMMIT_WIDTH];
logic [$clog2(PHYS_REGS)-1:0] commit_old_prf_o [COMMIT_WIDTH];
logic [XLEN-1:0] commit_value_o [COMMIT_WIDTH];

logic flush_o;
logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o;

// ================================
// Instantiate ROB
// ================================
ROB #(
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

// ================================
// 重置信號初始化 
// ================================

// Clock
always #5 clk = ~clk;
// Reset
initial begin
    clk = 0; reset = 1;
    repeat (3) @(negedge clk);
    reset = 0;
end

// =====================================================
// === 第一部分：原始多階段測試（testdata1）
// =====================================================
initial begin
    // === 初始化 ===
    disp_valid_i = '0; disp_rd_wen_i = '0;
    wb_valid_i   = '0; wb_exception_i = '0; wb_mispred_i = '0;

    @(negedge reset);
    @(negedge clk); // 等 reset 結束

    // -----------------------------
    // [Phase 1] Dispatch 一條指令，正常 commit
    // -----------------------------
    $display("\n=== Phase 1: 單一指令 Dispatch/Commit 測試 ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd1;
    disp_rd_new_prf_i[0] = 7'd10;
    disp_rd_old_prf_i[0] = 7'd2;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback 該指令 (ROB idx 0)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 0;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 2] 同時 dispatch 兩條，writeback 一條，另一條延遲
    // =====================================================
    $display("\n=== Phase 2: 雙發射交錯 Writeback 測試 ===");
    @(negedge clk);
    disp_valid_i      = 2'b11;
    disp_rd_wen_i     = 2'b11;
    disp_rd_arch_i[0] = 5'd3; disp_rd_new_prf_i[0] = 7'd11; disp_rd_old_prf_i[0] = 7'd5;
    disp_rd_arch_i[1] = 5'd4; disp_rd_new_prf_i[1] = 7'd12; disp_rd_old_prf_i[1] = 7'd6;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback 第一條（ROB idx 1）
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 1;

    @(negedge clk);
    wb_valid_i = '0;

    // 延遲幾拍再 writeback 第二條（ROB idx 2）
    repeat (3) @(negedge clk);
    wb_valid_i[1]   = 1;
    wb_rob_idx_i[1] = 2;

    @(negedge clk);
    wb_valid_i = '0;

    repeat (6) @(negedge clk);

    // -----------------------------
    // Phase 3：分支錯誤觸發 flush 測試
    // -----------------------------
    $display("\n=== Phase 3: 分支預測錯誤 Flush 測試 ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd7;
    disp_rd_new_prf_i[0] = 7'd13;
    disp_rd_old_prf_i[0] = 7'd8;

    @(negedge clk);
    disp_valid_i = '0;

    // Writeback 該指令，標記 mispred (ROB idx 3)
    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 3;
    wb_mispred_i[0] = 1; // 觸發 flush

    @(negedge clk);
    wb_valid_i = '0; wb_mispred_i = '0;
    repeat (5) @(negedge clk);

    // =====================================================
    // [Phase 4] Flush 後重新 dispatch 新指令
    // =====================================================

    $display("\n=== Phase 4: Flush 後重新 Dispatch 測試 ===");
    @(negedge clk);
    disp_valid_i[0]      = 1;
    disp_rd_wen_i[0]     = 1;
    disp_rd_arch_i[0]    = 5'd9;
    disp_rd_new_prf_i[0] = 7'd14;
    disp_rd_old_prf_i[0] = 7'd4;

    @(negedge clk);
    disp_valid_i = '0;

    @(negedge clk);
    wb_valid_i[0]   = 1;
    wb_rob_idx_i[0] = 4;

    @(negedge clk);
    wb_valid_i = '0;
    repeat (8) @(negedge clk);

    $display("\n=== 第一階段測試完成 (testdata1 部分) ===");
end

// =====================================================
// === 第二部分：N-way 延伸測試（你的 rob_testdata_nway）
// =====================================================
initial begin
    @(negedge clk);
    #100;  // 等前半段完成後再開始

    $display("\n=== [延伸測試] N-way ROB 測試序列開始 ===");

    // -----------------------------
    // 發射兩條指令
    // -----------------------------
    disp_valid_i = 2'b11;
    disp_rd_wen_i = 2'b11;
    disp_rd_arch_i[0] = 3; disp_rd_new_prf_i[0] = 8; disp_rd_old_prf_i[0] = 3;
    disp_rd_arch_i[1] = 4; disp_rd_new_prf_i[1] = 9; disp_rd_old_prf_i[1] = 4;
    @(negedge clk); disp_valid_i = '0;
    $display("[Cycle %0t] 🚀 發射 I0, I1", $time);

    // -----------------------------
    // 寫回這兩條指令的值
    // -----------------------------
    #10;
    wb_valid_i = 4'b0011;
    wb_rob_idx_i[0] = 0; wb_value_i[0] = 64'h1111_1111_1111_0000;
    wb_rob_idx_i[1] = 1; wb_value_i[1] = 64'h2222_2222_2222_0000;
    @(negedge clk); wb_valid_i = '0;
    $display("[WB] I0, I1 寫回完成 (value=0x1111..., 0x2222...)");

    // -----------------------------
    // 模擬一條 mispredict 導致 flush
    // -----------------------------
    #10;
    wb_valid_i = 4'b0001;
    wb_rob_idx_i[0] = 2;
    wb_mispred_i = 4'b0001;
    wb_value_i[0] = 64'hDEAD_BEEF_1234_0000;
    @(negedge clk); wb_valid_i = '0; wb_mispred_i = '0;
    $display("[WB] I2 發生分支錯誤，預期觸發 FLUSH");

    // -----------------------------
    // 驗證 flush 與 commit 狀態
    // -----------------------------
    #20;
    if (flush_o)
    $display("✅ 測試通過：Flush 於 ROB[%0d] 觸發", flush_upto_rob_idx_o);
    else
    $display("❌ 測試失敗：未偵測到 Flush 觸發");

    if (|commit_valid_o)
    $display("✅ 偵測到 COMMIT 輸出");
    else
    $display("❌ 測試失敗：未偵測到 COMMIT");

    #50;
    $display("=== [延伸測試結束] N-way ROB 測試完成 ===");
    $finish;
end

    // Monitor
always @(negedge clk) begin
    for(int i = 0; i < )
    if (commit_valid_o[0])
    $display("[%0t] Commit: arch=%0d new=%0d old=%0d",
            $time, commit_rd_arch_o[0],
            commit_new_prf_o[0], commit_old_prf_o[0]);
    if (flush_o)
    $display("[%0t] Flush up to ROB idx %0d", $time, flush_upto_rob_idx_o);
end

endmodule
