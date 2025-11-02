`timescale 1ns/1ps
`include "defs.svh"

// =========================================================
// Testbench for CDB
// =========================================================
module cdb_tb;

    // -----------------------------
    // Parameters
    // -----------------------------
    localparam int CDB_WIDTH  = 2;
    localparam int PHYS_REGS  = 128;
    localparam int ARCH_REGS  = 32;
    localparam int ROB_DEPTH  = 64;
    localparam int XLEN       = 64;

    // -----------------------------
    // DUT Ports
    // -----------------------------
    logic clk;
    logic reset;
    cdb_entry_t [CDB_WIDTH-1:0] cdb_packets_i;

    logic [CDB_WIDTH-1:0] cdb_valid_rs_o;
    logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] cdb_tag_rs_o;

    logic [CDB_WIDTH-1:0] cdb_valid_mp_o;
    logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] cdb_phy_tag_mp_o;
    logic [CDB_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] cdb_dest_arch_mp_o;

    logic rs_ready_i;
    logic map_ready_i;

    // -----------------------------
    // Clock generation
    // -----------------------------
    initial clk = 0;
    always #5 clk = ~clk; // 10ns period

    // -----------------------------
    // DUT Instantiation
    // -----------------------------
    cdb #(
        .CDB_WIDTH (CDB_WIDTH),
        .PHYS_REGS (PHYS_REGS),
        .ARCH_REGS (ARCH_REGS),
        .ROB_DEPTH (ROB_DEPTH),
        .XLEN      (XLEN)
    ) dut (
        .clk(clk),
        .reset(reset),
        .cdb_packets_i(cdb_packets_i),
        .cdb_valid_rs_o(cdb_valid_rs_o),
        .cdb_tag_rs_o(cdb_tag_rs_o),
        .cdb_valid_mp_o(cdb_valid_mp_o),
        .cdb_phy_tag_mp_o(cdb_phy_tag_mp_o),
        .cdb_dest_arch_mp_o(cdb_dest_arch_mp_o),
        .rs_ready_i(rs_ready_i),
        .map_ready_i(map_ready_i)
    );

    // =========================================================
    // Task: send one CDB packet
    // =========================================================
    task send_cdb(
        input int idx,
        input logic valid,
        input logic [$clog2(PHYS_REGS)-1:0] phys_tag,
        input logic [$clog2(ARCH_REGS)-1:0] dest_arch
    );
        begin
            cdb_packets_i[idx].valid     = valid;
            cdb_packets_i[idx].phys_tag  = phys_tag;
            cdb_packets_i[idx].dest_arch = dest_arch;
        end
    endtask

    // =========================================================
    // Test Sequence
    // =========================================================
    initial begin
        // Initialize
        clk = 0;
        reset = 1;
        rs_ready_i = 1;
        map_ready_i = 1;
        cdb_packets_i = '0;
        #20;
        reset = 0;

        $display("===== TEST 1: Normal broadcast =====");
        send_cdb(0, 1'b1, 6'd10, 5'd1);
        send_cdb(1, 1'b1, 6'd11, 5'd2);
        @(posedge clk);
        #1;
        $display("[CDB OUT] valid_rs=%b tag_rs=%p valid_mp=%b phy_mp=%p dest_mp=%p",
            cdb_valid_rs_o, cdb_tag_rs_o, cdb_valid_mp_o, cdb_phy_tag_mp_o, cdb_dest_arch_mp_o);

        // Clear inputs
        send_cdb(0, 1'b0, '0, '0);
        send_cdb(1, 1'b0, '0, '0);
        @(posedge clk);

        $display("===== TEST 2: Stall condition (map_ready_i = 0) =====");
        rs_ready_i = 1;
        map_ready_i = 0;
        send_cdb(0, 1'b1, 6'd12, 5'd3);
        send_cdb(1, 1'b1, 6'd13, 5'd4);
        @(posedge clk);
        #1;
        $display("[STALL] Should not update (cdb_stall active)");
        $display("[CDB OUT] valid_rs=%b tag_rs=%p valid_mp=%b phy_mp=%p dest_mp=%p",
            cdb_valid_rs_o, cdb_tag_rs_o, cdb_valid_mp_o, cdb_phy_tag_mp_o, cdb_dest_arch_mp_o);

        // De-stall and send new
        map_ready_i = 1;
        send_cdb(0, 1'b1, 6'd20, 5'd5);
        send_cdb(1, 1'b1, 6'd21, 5'd6);
        @(posedge clk);
        #1;
        $display("===== TEST 3: After de-stall =====");
        $display("[CDB OUT] valid_rs=%b tag_rs=%p valid_mp=%b phy_mp=%p dest_mp=%p",
            cdb_valid_rs_o, cdb_tag_rs_o, cdb_valid_mp_o, cdb_phy_tag_mp_o, cdb_dest_arch_mp_o);

        $display("===== TEST COMPLETE =====");
        #20;
        $finish;
    end

endmodule