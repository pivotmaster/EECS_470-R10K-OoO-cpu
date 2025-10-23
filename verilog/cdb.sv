/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  CDB.sv                                              //
//                                                                     //
//  Description :  Complate Stage -> CDB -> [RS & Map Table]           //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "defs.svh"


module cdb #(
    parameter int unsigned CDB_WIDTH  = 2,
    parameter int unsigned PHYS_REGS  = 128,
    parameter int unsigned ROB_DEPTH  = 64,
    parameter int unsigned XLEN       = 64
)(
    input  logic clk,
    input  logic reset,

    // =========================================================
    // Complate Stage -> CDB 
    // =========== ============================================== 
    input  logic        [CDB_WIDTH-1:0]                         complete_cdb_valid_i,
    input  cdb_entry_t  [CDB_WIDTH-1:0]                         cdb_packets_i,

    // =========================================================
    // CDB -> RS 
    // =========================================================   
    output  logic [CDB_WIDTH-1:0]                               cdb_valid_rs_o, 
    output  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]        cdb_tag_rs_o,

    // =========================================================
    // CDB -> Map Table 
    // =========================================================   
    output  logic [CDB_WIDTH-1:0]                               cdb_valid_mp_o,  // commit_valid_i in 'map_table.sv'
    output  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]        cdb_phy_tag_mp_o,
    output  logic [CDB_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]        cdb_dest_arch_mp_o

)
endmodule
