`timescale 1ns/1ps


module rob_testdata_depchain_nway;
  parameter int N = 4;          // N-way superscalar issue width
  parameter int WIDTH = 32;     // instruction width

  logic clk, reset, flush;

  // issue interface
  logic [N-1:0]               issue_valid;
  logic [N-1:0][WIDTH-1:0]    issue_inst;
  logic [N-1:0][4:0]          issue_rd;
  logic [N-1:0][WIDTH-1:0]    issue_val;

  // clock generation
  always #5 clk = ~clk;

  initial begin
    clk = 0;
    reset = 1;
    flush = 0;
    issue_valid = '0;

    #10 reset = 0;
    $display("=== [Start N-way Dependency Chain Test] ===");

    // ----------------------------------------------------------
    // Cycle 1: issue I0, I1
    // I0: R3 = R1 + R2
    // I1: R4 = R3 - R1
    // ----------------------------------------------------------
    issue_valid[0] = 1; issue_inst[0] = 32'h00B101B3; issue_rd[0] = 5'd3; issue_val[0] = 32'h0;
    issue_valid[1] = 1; issue_inst[1] = 32'h40118233; issue_rd[1] = 5'd4; issue_val[1] = 32'h0;
    for (int i = 2; i < N; i++) issue_valid[i] = 0;
    #10 issue_valid = '0;
    $display("[Cycle %0t] Issued I0, I1", $time);

    // ----------------------------------------------------------
    // Cycle 2: issue I2, I3
    // I2: R1 = R1 + R2
    // I3: R2 = R1 + 5
    // ----------------------------------------------------------
    #10;
    issue_valid[0] = 1; issue_inst[0] = 32'h00B080B3; issue_rd[0] = 5'd1; issue_val[0] = 32'h0;
    issue_valid[1] = 1; issue_inst[1] = 32'h00508113; issue_rd[1] = 5'd2; issue_val[1] = 32'h0;
    for (int i = 2; i < N; i++) issue_valid[i] = 0;
    #10 issue_valid = '0;
    $display("[Cycle %0t] Issued I2, I3", $time);

    // ----------------------------------------------------------
    // Cycle 3: issue I4, I5
    // I4: R2 = R3 + R4
    // I5: R4 = R1 + R2
    // ----------------------------------------------------------
    #10;
    issue_valid[0] = 1; issue_inst[0] = 32'h00418133; issue_rd[0] = 5'd2; issue_val[0] = 32'h0;
    issue_valid[1] = 1; issue_inst[1] = 32'h00B202B3; issue_rd[1] = 5'd4; issue_val[1] = 32'h0;
    for (int i = 2; i < N; i++) issue_valid[i] = 0;
    #10 issue_valid = '0;
    $display("[Cycle %0t] Issued I4, I5", $time);

    // ----------------------------------------------------------
    // Cycle 4: issue I6
    // I6: R1 = R3 + 7
    // ----------------------------------------------------------
    #10;
    issue_valid[0] = 1; issue_inst[0] = 32'h00718113; issue_rd[0] = 5'd1; issue_val[0] = 32'h0;
    for (int i = 1; i < N; i++) issue_valid[i] = 0;
    #10 issue_valid = '0;
    $display("[Cycle %0t] Issued I6", $time);

    // ----------------------------------------------------------
    // Cycle 5: 模擬 branch mispredict → flush
    // ----------------------------------------------------------
    #10;
    flush = 1;
    $display("[Cycle %0t] Triggered FLUSH (mispredict recovery)", $time);
    #10 flush = 0;

    // ----------------------------------------------------------
    // Cycle 6: 再 issue 新指令確認 ROB 可恢復
    // ----------------------------------------------------------
    #10;
    issue_valid[0] = 1; issue_inst[0] = 32'h00B50533; issue_rd[0] = 5'd10; issue_val[0] = 32'h0; // ADD
    issue_valid[1] = 1; issue_inst[1] = 32'h40C60633; issue_rd[1] = 5'd12; issue_val[1] = 32'h0; // SUB
    for (int i = 2; i < N; i++) issue_valid[i] = 0;
    #10 issue_valid = '0;
    $display("[Cycle %0t] Issued recovery instructions", $time);

    #50;
    $display("=== [End of N-way Dependency Chain Test] ===");
    $finish;
  end
endmodule
