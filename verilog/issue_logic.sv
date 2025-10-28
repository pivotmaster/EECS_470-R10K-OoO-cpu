`timescale 1ns/1ps
`include "def.svh"

module issue_logic #(
    parameter int unsigned RS_DEPTH        = 64, //RS entry numbers
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned ISSUE_WIDTH     = 2,
    parameter int unsigned CDB_WIDTH       = 2,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned OPCODE_N        = 8,  //number of opcodes
    parameter int unsigned FU_NUM          = 6,  // how many different FU
    parameter int unsigned MAX_FIFO_DEPTH  = 4,  // Remaining FIFO space for each FU
    parameter int unsigned XLEN            = 64,
    parameter int ALU_COUNT   = 1,
    parameter int MUL_COUNT   = 1,
    parameter int LOAD_COUNT  = 1,
    parameter int BR_COUNT    = 1
)(
    input  logic                                                  clock,
    input  logic                                                  reset,

    // =========================================================
    // RS -> Issue Logic
    // =========================================================
    input  rs_entry_t    [RS_DEPTH-1:0]             rs_entries_i,
    input  logic         [RS_DEPTH-1:0]             rs_ready_i,
    input  fu_type_e                                fu_types_i [RS_DEPTH],

    output logic         [RS_DEPTH-1:0]             issue_enable_o, // which rs slot is going to be issued

    // =========================================================
    // FU <-> Issue logic
    // =========================================================
    //input   logic          [$clog2(MAX_FIFO_DEPTH)-1:0] fu_free_slots [FU_NUM], // Remaining FIFO space for each FU
    input logic   alu_ready_i  [ALU_COUNT],
    input logic   mul_ready_i  [MUL_COUNT],
    input logic   load_ready_i [LOAD_COUNT],
    input logic   br_ready_i   [BR_COUNT],

    output  issue_packet_t alu_req_o  [ALU_COUNT], // pkts to ALU 
    output  issue_packet_t mul_req_o  [MUL_COUNT],
    output  issue_packet_t load_req_o [LOAD_COUNT],
    output  issue_packet_t br_req_o   [BR_COUNT]
);

    // =========================================================
    // Grant Issue permission to RS entry (by issue selector)
    // =========================================================
    // Select who can issue ('issue_enable')
    logic [RS_DEPTH-1:0] issue_enable_o_next;  // internal signal

    issue_selector #(
        .RS_DEPTH(RS_DEPTH),
        .FU_NUM(FU_NUM),
        .ISSUE_WIDTH(ISSUE_WIDTH)
    )issue_sel(
        .fu_fifo_full(fu_fifo_full),
        .rs_ready_vec(rs_ready_i),
        .fu_types(fu_types_i),
        .issue_rs_entry(issue_enable_o_next)
    );

    // Prevent issue_enable_o -> affect RS (input of issue selector) at the same cycle
    always_ff @( posedge clock or posedge reset) begin 
        //$display("issue_enable_o_ = %b | issue_enable_o_next = %b", issue_enable_o, issue_enable_o_next);
        if (reset) begin
            issue_enable_o <= '0;
        end else begin
            issue_enable_o <= issue_enable_o_next;
        end
    end

    // =========================================================
    // Issue logic -> FU
    // =========================================================
    // Packets that sent to the FIFOs
    issue_packet_t issue_pkts [ISSUE_WIDTH]     ;    // packets to FIFOs
    logic [ISSUE_WIDTH-1:0] issue_pkt_rs_idx; // store the idx of RS entry for each issue pkt

    // Generate Issue Packets
    always_comb begin : issue_output
        int issue_slot = 0;

        for (int j = 0; j < ISSUE_WIDTH; j++) begin
            issue_pkts[j].valid = 0;
            issue_pkt_rs_idx[j] = '0;
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_enable_o_next[i]) begin
                //store rs enrty idx
                issue_pkt_rs_idx[issue_slot] = i;
                // create issue packet
                issue_pkts[issue_slot].valid = 1;
                issue_pkts[issue_slot].rob_idx  = rs_entries_i[i].rob_idx;
                issue_pkts[issue_slot].imm      = rs_entries_i[i].imm;
                issue_pkts[issue_slot].fu_type  = rs_entries_i[i].fu_type;
                issue_pkts[issue_slot].opcode   = rs_entries_i[i].opcode;
                issue_pkts[issue_slot].dest_tag = rs_entries_i[i].dest_tag;
                issue_pkts[issue_slot].src1_val = rs_entries_i[i].src1_tag; // src1_val should be tag
                issue_pkts[issue_slot].src2_val = rs_entries_i[i].src1_tag; // src2_val should be tag
                issue_slot++;
            end 
        end

        // Sent to FUs
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            if (issue_pkts[i].fu_type == FU_ALU && alu_ready_i ) begin
                alu_req_o  = issue_pkts[i];
                issue_enable_o_next[issue_pkt_rs_idx[i]] = 1'b1; 
            end else if (issue_pkts[i].fu_type == FU_MUL && mul_ready_i) begin
                mul_req_o  = issue_pkts[i];
                issue_enable_o_next[issue_pkt_rs_idx[i]] = 1'b1; 
            end else if (issue_pkts[i].fu_type == FU_LOAD && load_ready_i ) begin
                load_req_o = issue_pkts[i];
                issue_enable_o_next[issue_pkt_rs_idx[i]] = 1'b1; 
            end else if (issue_pkts[i].fu_type == FU_BRANCH && br_ready_i ) begin
                branch_req_o = issue_pkts[i];
                issue_enable_o_next[issue_pkt_rs_idx[i]] = 1'b1; 
            end
        end
    end

endmodule