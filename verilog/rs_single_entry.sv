
// =========================================================
// 1. disp_enable_i & empty => sent instr to rs_entry, empty = 0 (not empty)
// 2. if src1&2 ready => sent ready = 1 back to rs control module 
// 3. issue_enable_i & src1/2 ready => sent tpm_pkt to output_pkt (1 cycle latency)
// =========================================================
`include "def.svh"

module rs_single_entry #(
    parameter int unsigned PHYS_REGS    = 128,
    parameter int unsigned CDB_WIDTH    = 2,
    parameter int unsigned FU_NUM       = 8
)(
    input                                                clk, reset, flush,

    // Dispatch interface
    input  logic                                         disp_enable_i,
    input  rs_entry_t                                    rs_packets_i,
    output logic                                         empty_o,

    // Issue interface
    input  logic                                         issue_i, 

    output rs_entry_t                                    rs_single_entry_o,
    output logic [$clog2(FU_NUM)-1:0]                    fu_type_o,
    output logic                                         ready_o, // to rs control module
    
    //output logic                                         rs_issue_valid_single_o, // to issue logic module (reg)
    //output issue_packet_t                                rs_issue_pkt_single_o, // to issue logic module

    // CDB interface
    input  logic [CDB_WIDTH-1:0]                         cdb_valid_single_i, 
    input  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  cdb_tag_single_i
);  

    // =========================================================
    // Internal control signal
    // =========================================================
    logic           src1_ready, src2_ready; //reg
    logic           src1_hit, src2_hit;
    logic           empty, empty_next;
    rs_entry_t      rs_entry, rs_entry_next; // reg

    // =========================================================
    // CDB Wakeup
    //
    // When cdb tag arrive => pull up ready at the same cycle (comb) & store src1_ready at the next cycle (reg).
    // This let [CDB wakeup & RS receive tag] at the same cycle
    // =========================================================
    always_comb begin: cdb
        src1_hit = 1'b0;
        src2_hit = 1'b0;
        for (int k = 0; k < CDB_WIDTH; k++) begin
            if (cdb_valid_single_i[k] && (cdb_tag_single_i[k] == rs_entry.src1_tag))
            src1_hit = 1'b1; 
            if (cdb_valid_single_i[k] && (cdb_tag_single_i[k] == rs_entry.src2_tag))
            src2_hit = 1'b1;
        end
    end

    // =========================================================
    // RS entry update
    // =========================================================
    // Update to RS entry 
    always_comb begin : update_rs_entry
        rs_entry_next = rs_entry;
        empty_next    = empty;

        if (flush) begin
            rs_entry_next = '{default:'0};
            empty_next    = 1'b1;
        end else if (disp_enable_i && empty) begin
            rs_entry_next = rs_packets_i;
            empty_next    = 1'b0;
        end else begin
            // CDB wake up
            rs_entry_next.src1_ready = rs_entry.src1_ready | src1_hit;
            rs_entry_next.src2_ready = rs_entry.src2_ready | src2_hit;

            // Clear RS entry after issue
            if (issue_i && ready_o) begin
                empty_next = 1'b1;
                rs_entry_next.valid = 1'b0;
            end
        end
    end

    // Save the update to register
    always_ff @(posedge clk) begin : update
        if (reset) begin
            rs_entry     <= '{default:'0}; 
            empty        <= 1'b1;
        end else
        if (flush) begin
            rs_entry     <= '{default:'0}; 
            empty        <= 1'b1;
        end else begin
            rs_entry     <= rs_entry_next;
            empty        <= empty_next;
        end
    end

    // =========================================================
    // Output part
    // =========================================================
    // Output to RS control logic
    assign empty_o   = empty;

    // Output to issue logic 
    assign ready_o   = (rs_entry.src1_ready || src1_hit) &&  (rs_entry.src2_ready || src2_hit);
    assign fu_type_o = rs_entry.fu_type; 
    assign rs_single_entry_o = rs_entry ;

endmodule

