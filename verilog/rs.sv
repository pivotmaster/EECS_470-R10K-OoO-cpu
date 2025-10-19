/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  RS.sv                                               //
//                                                                     //
//  Description :  operand value were access at dispatch stage         //
//                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "defs.svh"

module RS #(
    parameter int unsigned DEPTH           = 64,
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned ISSUE_WIDTH     = 2,
    parameter int unsigned CDB_WIDTH       = 2,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned OPCODE_N        = 8,  //number of opcodes
)(
    input  logic clk,
    input  logic reset,

    // =========================================================
    // Dispatch <-> RS
    // =========================================================
    input  logic       [DISPATCH_WIDTH-1:0]                    disp_valid_i,
    input  rs_entry_t  [DISPATCH_WIDTH-1:0]                    rs_packets_i,
    input  logic       [DISPATCH_WIDTH-1:0]                    disp_rs_rd_wen_i,     // read (I think it is whether write PRF?)

    output logic       [$clog2(DISPATCH_WIDTH)-1:0]            free_slot_o,      // how many slot is free? (saturate at DISPATCH_WIDTH)
    output logic                                               rs_full_o,
    output logic       [DISPATCH_WIDTH-1:0]                    disp_rs_ready_o, 

    // =========================================================
    // CDB -> RS 
    // =========================================================
    input  logic [CDB_WIDTH-1:0]                               cdb_valid_i, 
    input  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]        cdb_tag_i,

    // =========================================================
    // RS -> FU (Issue)
    // =========================================================
    output logic [ISSUE_WIDTH-1:0]                             issue_valid_o,
    output logic [ISSUE_WIDTH-1:0][$clog2(OPCODE_N)-1:0]       issue_opcode_o,    // which opcode it is
    output logic [ISSUE_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]      issue_dest_tag_o,  // destination register
    output logic [ISSUE_WIDTH-1:0][XLEN-1:0]                   issue_opa_tag_o,   // assume RS only store Tags
    output logic [ISSUE_WIDTH-1:0][XLEN-1:0]                   issue_opb_tag_o
    
);

endmodule

