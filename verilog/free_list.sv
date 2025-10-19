/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  free_list.sv                                        //
//                                                                     //
//  Description :      //
//                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

module free_list #(
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned COMMIT_WIDTH    = 2,
    parameter int unsigned PHYS_REGS       = 128,
)(
    input  logic clk,
    input  logic reset,

    // =========================================================
    // Dispatch <-> free list 
    // =========================================================
    input  logic [DISPATCH_WIDTH-1:0]                       alloc_req_i,

    output logic [DISPATCH_WIDTH-1:0]                       new_reg_o,
    output logic [$clog2(DISPATCH_WIDTH)-1:0]               free_regs_o,   // how many regsiters are free? (saturate at DISPATCH_WIDTH)
    output logic                                            empty_o,

    // =========================================================
    // Commit -> free list 
    // =========================================================
    input  logic [COMMIT_WIDTH-1:0]                         free_valid_i,  //not all instructions will release reg (ex:store)
    input  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  free_reg_i,     
);

endmodule