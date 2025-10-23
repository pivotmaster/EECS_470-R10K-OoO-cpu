
// =========================================================
// 1. disp_enable_i & empty => sent instr to rs_entry, empty = 0 (not empty)
// 2. if src1&2 ready => sent ready = 1 back to rs control module 
// 3. issue_enable_i & src1/2 ready => sent tpm_pkt to output_pkt (1 cycle latency)
// =========================================================
module rs_single_entry #(
    parameter int unsigned PHYS_REGS    = 128,
    parameter int unsigned CDB_WIDTH    = 2,
    parameter int unsigned FU_NUM       = 8,
)(
    input                                                clk, reset, 

    // Dispatch interface
    input  logic                                         disp_enable_i,
    input  rs_entry_t                                    rs_packets_i,
    output logic                                         empty_o,

    // Issue interface
    input  logic                                         issue_enable_i, // from rs control module
    output logic [$clog2(FU_NUM)-1:0]                    fu_type_o;
    output logic                                         ready_o, // to rs control module
    
    output logic                                         rs_issue_valid_single_o, // to issue logic module (reg)
    output issue_packet_t                                rs_issue_pkt_single_o, // to issue logic module

    // CDB interface
    input  logic [CDB_WIDTH-1:0]                         cdb_valid_single_i, 
    input  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  cdb_tag_single_i,
);  

    // internal control signal
    logic         src1_ready, src2_ready; //reg
    logic         src1_ready_wire, src2_ready_wire; //wire
    logic         empty, ready; //wire
    issue_packet  tpm_rs_issue_pkt; // reg
    issue_packet  empty_issue_pkt;  // comb

    // When cdb tag arrive => pull up ready at the same cycle (comb) & store src1_ready at the next cycle (reg).
    // This let [CDB wakeup & RS receive tag] at the same cycle 
    logic src1_hit, src2_hit;

    always_comb begin: cdb
        src1_hit = 1'b0;
        src2_hit = 1'b0;
        for (int k = 0; k < NUM_CDB; k++) begin
            if (cdb_valid_i[k] && (cdb_tag_i[k] == tpm_rs_issue_pkt.src1_tag))
            src1_hit = 1'b1;
            if (cdb_valid_i[k] && (cdb_tag_i[k] == tpm_rs_issue_pkt.src2_tag))
            src2_hit = 1'b1;
        end
    end

    assign ready = (src1_ready || src1_hit) &&  (src2_ready || src2_hit);

    //output
    assign empty_o = empty;
    assign ready_o = ready; 

    always_comb begin : empty_issue_packet
        empty_issue_pkt.valid    = 0;
        empty_issue_pkt.rob_idx  = 0;
        empty_issue_pkt.imm      = 0;
        empty_issue_pkt.fu_type  = 0;
        empty_issue_pkt.opcode   = 0;
        empty_issue_pkt.src1_tag = 0;
        empty_issue_pkt.src2_tag = 0;
    end

    always_ff @(posedge clk or posedge reset) begin : rs_control_to_rs_single
        if (reset) begin
            tpm_rs_issue_pkt <= empty_issue_pkt;
            rs_issue_pkt_o   <= empty_issue_pkt;
            rs_issue_valid_o <= 0;
            src1_ready       <= 0;
            src2_ready       <= 0;   
            empty            <= 1;
        end else if (disp_enable_i && empty) begin
            empty <= 0; // not empty
            tpm_rs_issue_pkt.valid    <= 1;
            tpm_rs_issue_pkt.rob_idx  <= rs_packets_i.rob_idx;
            tpm_rs_issue_pkt.imm      <= rs_packets_i.imm;
            tpm_rs_issue_pkt.fu_type  <= rs_packets_i.fu_type;
            tpm_rs_issue_pkt.opcode   <= rs_packets_i.opcode;
            tpm_rs_issue_pkt.dest_tag <= rs_packets_i.dest_tag;
            tpm_rs_issue_pkt.src1_tag <= rs_packets_i.src1_tag;
            tpm_rs_issue_pkt.src2_tag <= rs_packets_i.src2_tag;
            src1_ready                <= rs_packets_i.src1_ready;
            src2_ready                <= rs_packets_i.src2_ready;
        end else if (cdb_valid_single_i && !empty) begin
            if ((cdb_tag_single_i == tpm_rs_issue_pkt.src1_tag)) src1_ready <= 1;
            if ((cdb_tag_single_i == tpm_rs_issue_pkt.src2_tag)) src2_ready <= 1;
        end else if (issue_enable_i && ready) begin
            // sent to issue
            rs_issue_pkt_single_o   <= tpm_rs_issue_pkt;
            rs_issue_valid_single_o <= 1;
            // reset the signal one cycle after issue 
            empty            <= 1;
            src1_ready       <= 0;
            src2_ready       <= 0;
            tpm_rs_issue_pkt <= empty_issue_pkt;
        end else begin
            rs_issue_pkt_single_o   <= empty_issue_pkt;
            rs_issue_valid_single_o <= 0;
        end
    end

endmodule

