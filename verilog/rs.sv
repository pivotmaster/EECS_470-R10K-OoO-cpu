/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  RS.sv                                               //
//                                                                     //
//  Description :  operand value were access at dispatch stage         //
//                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

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
    input  logic [DISPATCH_WIDTH-1:0]                          disp_valid_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(OPCODE_N)-1:0]    opcode_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]   dest_tag_i,            // write reg
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]   src1_tag_i,       // source reg 1
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]   src1_tag_ready_i, // is value of source reg 1 ready?
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]   src2_tag_i,       // source reg 2
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]   src2_tag_ready_i, // is value of source reg 2 ready?

    output logic [$clog2(DISPATCH_WIDTH)-1:0]                  free_slot_o,      // how many slot is free? (saturate at DISPATCH_WIDTH)
    output logic                                               rs_full_o,

    // =========================================================
    // CDB -> RS 
    // =========================================================
    input  logic [CDB_WIDTH-1:0]                            cdb_valid_i, 
    input  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]     cdb_tag_i,

    // =========================================================
    // RS -> FU (Issue)
    // =========================================================
    output logic [ISSUE_WIDTH-1:0]                             issue_valid_o,
    output logic [ISSUE_WIDTH-1:0][$clog2(OPCODE_N)-1:0]       issue_opcode_o,    // which opcode it is
    output logic [ISSUE_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]      issue_dest_tag_o,  // destination register
    output logic [ISSUE_WIDTH-1:0][XLEN-1:0]                   issue_opa_tag_o,   // assume RS only store Tags
    output logic [ISSUE_WIDTH-1:0][XLEN-1:0]                   issue_opb_tag_o
    
);

    typedef struct packed {
        logic                          valid;     // = busy
        logic [8:0]                    fu_type;   // on hot code
        logic [$clog2(OPCODE_N)-1:0]   opcode;
        logic [$clog2(PHYS_REGS)-1:0]  dest_tag;
        logic [$clog2(PHYS_REGS)-1:0]  src1_tag;       
        logic [$clog2(PHYS_REGS)-1:0]  src2_tag;
        logic                          src1_ready;
        logic                          src2_ready;
    } rs_entry_t;

endmodule

