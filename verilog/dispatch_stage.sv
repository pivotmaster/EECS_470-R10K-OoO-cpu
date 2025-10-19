/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  dispatch_stage.sv                                   //
//                                                                     //
//  Description :  Decode -> Rename -> Dispatch (RS & ROB)             //
//                                                                     //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////


// =========================================================
// ????????? 
// [Fetch -> ROB -> RS] OR [Fetch -> ROB && RS]
// It seems like there was no datapath between ROB and RS in R10K? 
// =========================================================  

`include "defs.svh"

module decoder (
    input INST  inst,
    input logic valid, // when low, ignore inst. Output will look like a NOP

    output ALU_OPA_SELECT opa_select,
    output ALU_OPB_SELECT opb_select,
    output logic          has_dest, // if there is a destination register
    output ALU_FUNC       alu_func,
    output logic          mult, rd_mem, wr_mem, cond_branch, uncond_branch,
    output logic          csr_op, // used for CSR operations, we only use this as a cheap way to get the return code out
    output logic          halt,   // non-zero on a halt
    output logic          illegal // non-zero on an illegal instruction
);
endmodule

module dispatch_stage #(
    parameter int unsigned           FETCH_WIDTH     = 2,
    parameter int unsigned           DISPATCH_WIDTH  = 2,
    parameter int unsigned           ADDR_WIDTH      = 32

)(
    input   logic                                     clock,          
    input   logic                                     reset,         

    // =========================================================
    // Decode Instructions 
    // =========================================================  
    input   IF_ID_PACKET                              if_packet_i,     // get packet from Fetch Stage

    // =========================================================
    // (RENAME) Dispatch <-> Free List
    // =========================================================
    input  logic       [$clog2(DISPATCH_WIDTH)-1:0]   free_regs_i,   // how many regsiters in Free list? (saturate at DISPATCH_WIDTH)
    input  logic                                      empty_i,       // Whether Free list is empty
    input  logic       [DISPATCH_WIDTH-1:0]           new_reg_i,

    output logic       [DISPATCH_WIDTH-1:0]           alloc_req_o,   // request sent to Free List (return new_reg_o)

    // =========================================================
    // (RENAME) Dispatch <-> Map Table
    // =========================================================
    input   logic      [DISPATCH_WIDTH-1:0]                           src1_ready_i,  // <-> rs1_valid_o in 'map_table.sv' 
    input   logic      [DISPATCH_WIDTH-1:0]                           src2_ready_i,
    input   logic      [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]    src1_phys_i,   //tag of reg 1
    input   logic      [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]    src2_phys_i,   //tag of reg 2
    input   logic      [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]    dest_reg_old_i,  //Told

    output  logic      [DISPATCH_WIDTH-1:0]                           rename_valid_o,
    output  logic      [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]    dest_arch_o,     //write reg   request
    output  logic      [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]    src1_arch_o,   //read  reg 1 request
    output  logic      [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]    src2_arch_o,   //read  reg 2 request

    // =========================================================
    // Dispatch <-> RS
    // =========================================================
    input  logic       [$clog2(DISPATCH_WIDTH)-1:0]                   free_rs_slots_i,      // how many free slots in rs
    input  logic                                                      rs_full_i,   
    input  logic       [DISPATCH_WIDTH-1:0]                           disp_rs_ready_i,   
    
    output logic       [DISPATCH_WIDTH-1:0]                           disp_rs_valid_o,
    output logic       [DISPATCH_WIDTH-1:0]                           disp_rs_rd_wen_o,       // read (I think it is whether write PRF?)
    output rs_entry_t  [DISPATCH_WIDTH-1:0]                           rs_packets_o,           // packets sent to rs

    // =========================================================
    // Dispatch <-> ROB
    // =========================================================
    input  logic       [$clog2(DISPATCH_WIDTH)-1:0]                   free_rob_slots_i,   // how many free slots in rob 
    input  logic       [DISPATCH_WIDTH-1:0]                           disp_rob_ready_i,   //rob is ready
    input  logic       [DISPATCH_WIDTH-1:0][$clog2(DEPTH)-1:0]        disp_rob_idx_i,     // rob id (sent to rs)

    output logic       [DISPATCH_WIDTH-1:0]                           disp_rob_valid_o,
    output logic       [DISPATCH_WIDTH-1:0]                           disp_rob_rd_wen_o, // read
    output rob_entry_t [DISPATCH_WIDTH-1:0]                           rob_packets_o,     // packets sent to rob

    // =========================================================
    // (branch update) Dispatch → BTB 
    // =========================================================
    output  logic                          btb_update_valid_o,
    output  logic      [ADDR_WIDTH-1:0]    btb_update_pc_o,
    output  logic      [ADDR_WIDTH-1:0]    btb_update_target_o,

);

endmodule


