/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  RS.sv                                               //
//                                                                     //
//  Description :        //
//                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "defs.svh"

module RS #(
    parameter int unsigned RS_DEPTH        = 64, //RS entry numbers
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned ISSUE_WIDTH     = 2,
    parameter int unsigned CDB_WIDTH       = 2,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned OPCODE_N        = 8,  //number of opcodes
    parameter int unsigned FU_NUM          = 8,  // how many different FU
    parameter int unsigned MAX_FU_PER_TYPE = 4,  // how many Fu per each FU type
    parameter int unsigned XLEN            = 64
)(
    input  logic                                                  clk,
    input  logic                                                  reset,

    // =========================================================
    // Dispatch <-> RS
    // =========================================================
    input  logic          [DISPATCH_WIDTH-1:0]                    disp_valid_i,
    input  rs_entry_t     [DISPATCH_WIDTH-1:0]                    rs_packets_i,
    input  logic          [DISPATCH_WIDTH-1:0]                    disp_rs_rd_wen_i,     // read (I think it is whether write PRF?)

    output logic          [$clog2(DISPATCH_WIDTH)-1:0]            free_slots_o,      // how many slot is free? (saturate at DISPATCH_WIDTH)
    output logic                                                  rs_full_o,

    // =========================================================
    // CDB -> RS 
    // =========================================================
    input  logic          [CDB_WIDTH-1:0]                         cdb_valid_i, 
    input  logic          [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  cdb_tag_i,

    // =========================================================
    // RS <-> FU (Issue)
    // =========================================================
    input  logic          [$clog2(MAX_FU_PER_TYPE)-1:0]           fu_status_i [FU_NUM],

    output logic          [ISSUE_WIDTH-1:0]                       issue_valid_o,
    output issue_packet_t [ISSUE_WIDTH-1:0]                       issue_pkt_o,    // packet for [rs -> issue]
    
); 
    // Dispatch signal
    logic         [RS_DEPTH-1:0]             disp_enable;
    rs_entry_t    [RS_DEPTH-1:0]             rs_packets;
    logic         [RS_DEPTH-1:0]             rs_empty;

    // Issue signal
    logic         [RS_DEPTH-1:0]             issue_enable;
    logic         [RS_DEPTH-1:0]             rs_ready;  
    logic         [$clog2(FU_NUM)-1:0]       fu_types [RS_DEPTH];

    logic         [RS_DEPTH-1:0]             rs_issue_valid;
    issue_packet  [RS_DEPTH-1:0]             rs_issue_pkts;

    // Dispatch_grant_rs_slot
    logic [DISPATCH_WIDTH-1:0][RS_DEPTH-1:0] disp_grant_vec;

    // =========================================================
    // Whole RS table
    // =========================================================
    genvar i;
    generate 
        for (i=0; i < RS_DEPTH; i++) begin
            rs_single_entry rs_entry #(
                .PHYS_REGS(PHYS_REGS),
                .CDB_WIDTH(CDB_WIDTH)
            )(
                .clk(clk),
                .reset(reset),
                .disp_enable_i(disp_enable[i]),
                .rs_packets_i(rs_packets[i]),
                .empty_o(rs_empty[i]),
                .issue_enable_i(issue_enable[i]),
                .fu_type_o(fu_types[i]),
                .ready_o(rs_ready[i]),
                .rs_issue_valid_single_o(rs_issue_valid[i]),
                .rs_issue_pkt_single_o(rs_issue_pkts[i]),
                .cdb_valid_single_i(cdb_valid_i),
                .cdb_tag_single_i(cdb_tag_i)
            );
        end
    endgenerate

    // =========================================================
    // Dispatch packet to RS entries
    // =========================================================

    // selector: select which rs entry to dispatch
    disp_selector disp_sel #(
        .RS_DEPTH(RS_DEPTH),
        .DISPATCH_WIDTH(DISPATCH_WIDTH)
    )(
        .empty_vec(rs_empty),
        .disp_valid_vec(disp_valid_i),
        .disp_grant_vec(disp_grant_vec)
    );

    // grant input packects to its corresponding rs entry (detemrine by rs_sel)
    always_comb begin: disp_pkt
        rs_packets  = '0;
        disp_enable = '0;
        for (int i = 0; i<DISPATCH_WIDTH; i++) begin
            for (int j=0; j<RS_DEPTH; j++) begin
                /* from gpt: assert if two granted to the same rs entry (only  for simulation)
                assert ($onehot0(disp_grant_vec[:, j])) else
                    $error("Multiple dispatch slots assigned to RS entry %0d!", j);
                */
                if (disp_grant_vec[i][j]) begin
                    rs_packets[j]  = rs_packets_i[i]; // dispatch slot i allocates RS entry j
                    disp_enable[j] = 1'b1;
                end
            end
        end
    end

    // =========================================================
    // Grant Issue permission to RS entry (by issue selector)
    // =========================================================

    // Get 'issue_enable' sent to the rs entry
    issue_selector issue_sel #(
        .RS_DEPTH(RS_DEPTH),
        .FU_NUM(FU_NUM),
        .MAX_FU_PER_TYPE(MAX_FU_PER_TYPE),
        .ISSUE_WIDTH(ISSUE_WIDTH)
    )(
        .fu_status_vec(fu_status_i),
        .rs_ready_vec(rs_ready),
        .fu_types(fu_types),
        .issue_rs_entry(issue_enable) 
    );

    // Turn 'rs_issue_valid' & 'rs_issue_pkts" to output (issue_valid_o &　issue_pkt_o)
    always_comb begin : issue_output
        // Default outputs
        issue_valid_o     = '0;
        issue_opcode_o    = '0;
        issue_dest_tag_o  = '0;
        issue_opa_tag_o   = '0;
        issue_opb_tag_o   = '0;

        int out_idx = 0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_issue_valid[i] && (out_idx < ISSUE_WIDTH)) begin
                issue_valid_o[out_idx] = 1'b1;
                issue_pkt_o[out_idx]   = rs_issue_pkts[i];
                out_idx++;
            end
        end
    end

    // =========================================================
    // Check remaining free slots (report to dispatch stage)
    // =========================================================
    always_comb begin : count_free_slot
        int free_slots = 0; 
        bit rs_full    = 0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_empty[i] && (free_slots < DISPATCH_WIDTH) ) begin
                free_slots++;
                rs_full = 1;
            end
        end
    end

    // assign results to output port
    assign rs_full_o    = rs_full;
    assign free_slots_o = free_slots;

endmodule

