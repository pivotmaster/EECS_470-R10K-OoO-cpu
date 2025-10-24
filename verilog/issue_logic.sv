module issue_logic #(
    parameter int unsigned RS_DEPTH        = 64, //RS entry numbers
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned ISSUE_WIDTH     = 2,
    parameter int unsigned CDB_WIDTH       = 2,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned OPCODE_N        = 8,  //number of opcodes
    parameter int unsigned FU_NUM          = 4,  // how many different FU
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
    input  logic         [2:0]                      fu_types_i [RS_DEPTH],

    output logic         [RS_DEPTH-1:0]             issue_enable_o, // which rs slot is going to be issued

    // =========================================================
    // FU <-> Issue logic
    // =========================================================
    input   logic          [$clog2(MAX_FIFO_DEPTH)-1:0] fu_free_slots [FU_NUM], // Remaining FIFO space for each FU
    input   logic          [FU_NUM-1:0]                 fu_fifo_full;

    output  logic          [FU_NUM-1:0]                 fu_fifo_wr_en;
    output  issue_packet_t [FU_NUM-1:0]                 fu_fifo_wr_pkt;

    // =========================================================
    // Issue logic <-> PRF
    // =========================================================
    input  logic         [XLEN-1:0]                  src_val
);

    // =========================================================
    // Grant Issue permission to RS entry (by issue selector)
    // =========================================================
    // Select who can issue ('issue_enable')
    issue_selector issue_sel #(
        .RS_DEPTH(RS_DEPTH),
        .FU_NUM(FU_NUM),
        .MAX_FU_PER_TYPE(MAX_FU_PER_TYPE),
        .ISSUE_WIDTH(ISSUE_WIDTH)
    )(
        .fu_fifo_full(fu_fifo_full),
        .rs_ready_vec(rs_ready_i),
        .fu_types(fu_types_i),
        .issue_rs_entry(issue_enable_o)
    );

    // =========================================================
    // Issue logic -> FIFO
    // =========================================================
    // Packets that sent to the FIFOs
    issue_packet_t [ISSUE_WIDTH-1:0]     issue_pkts,    // packets to FIFOs

    // Generate Issue Packets
    always_comb begin : issue_output
        for (int idx =0; idx <ISSUE_WIDTH; idx++) begin
            issue_pkt_o[idx].valid = 0;
        end

        int issue_slot = 0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_enable_o[i] && int issue_slot < ISSUE_WIDTH) begin
                issue_pkts[issue_slot].valid = 1;
                issue_pkts[issue_slot].rob_idx  = rs_entries_i[i].rob_idx;
                issue_pkts[issue_slot].imm      = rs_entries_i[i].imm;
                issue_pkts[issue_slot].fu_type  = rs_entries_i[i].fu_type;
                issue_pkts[issue_slot].opcode   = rs_entries_i[i].opcode;
                issue_pkts[issue_slot].dest_tag = rs_entries_i[i].dest_tag;
                issue_pkts[issue_slot].src1_val = //get prf value
                issue_pkts[issue_slot].src2_val = //get prf value
                issue_slot++;
            end
        end
    end

    // =========================================================
    // Route to FU : Route issued packets into FU FIFO
    // =========================================================
    always_comb begin : route_to_fu
        fu_fifo_wr_en  = '0;
        fu_fifo_wr_pkt = '{default:'0};

        // Loop over each issued instruction
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            if (issue_pkt_o[i].valid) begin
                unique case (issue_pkt_o[i].fu_type)

                    // ALU
                    FU_ALU: begin
                        if (!fu_fifo_full[0]) begin
                            fu_fifo_wr_en[0]  = 1'b1;
                            fu_fifo_wr_pkt[0] = issue_pkt_o[i];
                        end
                        else if (!fu_fifo_full[1]) begin
                            fu_fifo_wr_en[1]  = 1'b1;
                            fu_fifo_wr_pkt[1] = issue_pkt_o[i];
                        end
                        else if (!fu_fifo_full[2]) begin
                            fu_fifo_wr_en[2]  = 1'b1;
                            fu_fifo_wr_pkt[2] = issue_pkt_o[i];
                        end
                        // else: all ALU FIFOs full → stall
                    end

                    // MUL
                    FU_MUL: begin
                        if (!fu_fifo_full[3]) begin
                            fu_fifo_wr_en[3]  = 1'b1;
                            fu_fifo_wr_pkt[3] = issue_pkt_o[i];
                        end
                    end

                    // LOAD
                    FU_LOAD: begin
                        if (!fu_fifo_full[4]) begin
                            fu_fifo_wr_en[4]  = 1'b1;
                            fu_fifo_wr_pkt[4] = issue_pkt_o[i];
                        end
                    end

                    // BRANCH
                    FU_BRANCH: begin
                        if (!fu_fifo_full[5]) begin
                            fu_fifo_wr_en[5]  = 1'b1;
                            fu_fifo_wr_pkt[5] = issue_pkt_o[i];
                        end
                    end

                    default: ;
                endcase
            end
        end
    end

endmodule