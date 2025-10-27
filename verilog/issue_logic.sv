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
    parameter int unsigned XLEN            = 64
)(
    input  logic                                                  clk,
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
    input   logic          [FU_NUM-1:0]                 fu_fifo_full,

    output  logic          [FU_NUM-1:0]                 fu_fifo_wr_en,
    output  issue_packet_t                              fu_fifo_wr_pkt[FU_NUM],

    // =========================================================
    // Issue logic <-> PRF
    // =========================================================
    input   logic          [XLEN-1:0]                   src_val_a   [ISSUE_WIDTH],
    input   logic          [XLEN-1:0]                   src_val_b   [ISSUE_WIDTH],

    output  logic          [$clog2(PHYS_REGS)-1:0]      read_addr_a [ISSUE_WIDTH],
    output  logic          [$clog2(PHYS_REGS)-1:0]      read_addr_b [ISSUE_WIDTH]

);

    // =========================================================
    // Grant Issue permission to RS entry (by issue selector)
    // =========================================================
    // Select who can issue ('issue_enable')
    logic [RS_DEPTH-1:0] issue_enable_o_next;  // internal signal
    logic [FU_NUM-1:0]   fu_fifo_wr_en_next;
    issue_packet_t       fu_fifo_wr_pkt_next [FU_NUM];

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
    always_ff @( posedge clk or posedge reset) begin 
        //$display("issue_enable_o_ = %b | issue_enable_o_next = %b", issue_enable_o, issue_enable_o_next);
        if (reset) begin
            issue_enable_o <= '0;
            fu_fifo_wr_en   <= '0;
            fu_fifo_wr_pkt  <= '{default:'0};
        end else begin
            issue_enable_o <= issue_enable_o_next;
            fu_fifo_wr_en   <= fu_fifo_wr_en_next;
            fu_fifo_wr_pkt  <= fu_fifo_wr_pkt_next;
        end
    end

    // =========================================================
    // Issue logic -> FIFO
    // =========================================================
    // Packets that sent to the FIFOs
    issue_packet_t issue_pkts [ISSUE_WIDTH]     ;    // packets to FIFOs
    logic          [FU_NUM-1:0]    tmp_fu_full;
    logic test;

    // Generate Issue Packets
    always_comb begin : issue_output
        int issue_slot = 0;

        for (int j = 0; j < ISSUE_WIDTH; j++) begin
            issue_pkts[j].valid = 0;
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_enable_o_next[i]) begin
                // Get Value from PRF
                read_addr_a[issue_slot] = rs_entries_i[i].src1_tag;
                read_addr_b[issue_slot] = rs_entries_i[i].src2_tag;
                // Ohter fields
                issue_pkts[issue_slot].valid = 1;
                issue_pkts[issue_slot].rob_idx  = rs_entries_i[i].rob_idx;
                issue_pkts[issue_slot].imm      = rs_entries_i[i].imm;
                issue_pkts[issue_slot].fu_type  = rs_entries_i[i].fu_type;
                issue_pkts[issue_slot].opcode   = rs_entries_i[i].opcode;
                issue_pkts[issue_slot].dest_tag = rs_entries_i[i].dest_tag;
                issue_pkts[issue_slot].src1_val = src_val_a[issue_slot]; //get prf value
                issue_pkts[issue_slot].src2_val = src_val_b[issue_slot]; //get prf value
                issue_slot++;
            end 
        end
    end

    // =========================================================
    // Route to FU : Route issued packets into FU FIFO
    // =========================================================
    always_comb begin : route_to_fu
        fu_fifo_wr_en_next  = '0;
        fu_fifo_wr_pkt_next = '{default:'0};
        tmp_fu_full = fu_fifo_full;
        test =0;

        // Loop over each issued instruction
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            if (issue_pkts[i].valid) begin
                case (issue_pkts[i].fu_type)
                    // ALU
                    FU_ALU: begin
                        if (!tmp_fu_full[0]) begin
                            fu_fifo_wr_en_next[0]  = 1'b1;
                            fu_fifo_wr_pkt_next[0] = issue_pkts[i];
                            tmp_fu_full[0] = 1'b1;
                        end
                        else if (!tmp_fu_full[1]) begin
                            fu_fifo_wr_en_next[1]  = 1'b1;
                            fu_fifo_wr_pkt_next[1] = issue_pkts[i];
                            tmp_fu_full[1] = 1'b1;
                        end
                        else if (!tmp_fu_full[2]) begin
                            test = 2;
                            fu_fifo_wr_en_next[2]  = 1'b1;
                            fu_fifo_wr_pkt_next[2] = issue_pkts[i];
                            tmp_fu_full[2] = 1'b1;
                        end
                        // else: all ALU FIFOs full → stall
                    end

                    // MUL
                    FU_MUL: begin
                        if (!tmp_fu_full[3]) begin
                            fu_fifo_wr_en_next[3]  = 1'b1;
                            fu_fifo_wr_pkt_next[3] = issue_pkts[i];
                            tmp_fu_full[3] = 1'b1;
                        end
                    end

                    // LOAD
                    FU_LOAD: begin
                        if (!tmp_fu_full[4]) begin
                            fu_fifo_wr_en_next[4]  = 1'b1;
                            fu_fifo_wr_pkt_next[4] = issue_pkts[i];
                            tmp_fu_full[4] = 1'b1;
                        end
                    end

                    // BRANCH
                    FU_BRANCH: begin
                        if (!tmp_fu_full[5]) begin
                            fu_fifo_wr_en_next[5]  = 1'b1;
                            fu_fifo_wr_pkt_next[5] = issue_pkts[i];
                            tmp_fu_full[5] = 1'b1;
                        end
                    end

                    default: ;
                endcase
            end
        end
    end

endmodule