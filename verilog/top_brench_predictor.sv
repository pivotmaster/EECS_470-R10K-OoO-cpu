/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  top_brench_predictor.sv                                               //
//                                                                     //
//  Description :  operand value were access at dispatch stage         //
//                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

    // =========================================================
    // when to send request to brench predictor? 
    // fetch -> bp OR  (choosr this one)
    // decode (make sure it is brench instruciton) -> bp? 
    // =========================================================

    // =========================================================
    // OVERALL FLOW:
    // fetch -> BTB (is it a brench?) && BHT(G/P Share, meta predictor) 
    //       -> Mux (G or P Share, decide by meta) -> taken/ non-taken
    // =========================================================

// =========================================================
// BTB: Record [Instr -> target Addr]
// =========================================================
module btb #(
    parameter int unsigned           PHT_ENTRY_NUM  = 1024,
    parameter int unsigned           ADDR_WIDTH     = 64     // = address bits

)(
    input  logic                     clk,
    input  logic                     reset,

    // =========================================================
    // fetch <-> btb (is it a brench instr?)
    // =========================================================
    input  logic [ADDR_WIDTH-1:0]    pc_addr_i,   // real (physical) addr

    output logic                     is_branch_o, // is brench && has appeared before
    output logic [ADDR_WIDTH-1:0]    btb_target_o,

    // =========================================================
    // Dispatch → BTB : branch update 
    // =========================================================
    input  logic                     btb_update_valid_i,
    input  logic [ADDR_WIDTH-1:0]    btb_update_pc_i,
    input  logic [ADDR_WIDTH-1:0]    btb_update_target_i,
);

endmodule

// =========================================================
// Gshare Predictor: Include [GHR + BHT (2-bit)]
// =========================================================
module gshare_predictor #(
    parameter int unsigned           PHT_ENTRY_NUM  = 1024,
    parameter int unsigned           BHT_ENTRIES    = 1024,  // how many entries in history table
    parameter int unsigned           GHR_BITS       = $clog2(BHT_ENTRIES),  // record how many history events in GHR   
    parameter int unsigned           ADDR_WIDTH     = 64     // = address bits

)(
    input  logic                     clk,
    input  logic                     reset,

    // =========================================================
    // fetch <-> pht 
    // =========================================================
    input  logic [ADDR_WIDTH-1:0]    pc_addr_i,      // real (physical) addr
    output logic                     gsh_taken_o,    // 0 = non taken, 1 = taken

    // =========================================================
    // Execute → BTB : prediction update 
    // =========================================================
    input  logic                     gshare_update_valid_i,
    input  logic [ADDR_WIDTH-1:0]    gshare_update_pc_i,
    input  logic                     gshare_update_taken_i
) ;

    // GHR
    logic [GHR_BITS-1:0] ghr, ghr_next;  
   
    // BHT (2-bit counter)
    logic [1:0] BHT [BHT_ENTRIES-1:0]; // idx = PC_low_bits ^ GHR;

endmodule


// =========================================================
// Top Module for Branch Predict
// =========================================================
module top_brench_predictor #(
    parameter int unsigned           BTB_ENTRY_NUM = 256,
    parameter                        BHT_ENTRIES    = 1024,  // how many entries in history table
    parameter                        GHR_BITS       = 7,     // record how many history events in GHR 
    parameter int unsigned           ADDR_WIDTH    = 32    // = address bits
)(
    input  logic                     clk,
    input  logic                     reset,

    // =========================================================
    // fetch <-> bp 
    // =========================================================
    input  logic [ADDR_WIDTH-1:0]    pc_addr_i,       // real (physical) addr

    output logic                     is_branch_o,     // is prediction valid (btb hit?)
    output logic                     brench_taken_o,  // brench_taken = is_branch_o && gsh_taken_i
    output logic [ADDR_WIDTH-1:0]    target_addr_o  

    // =========================================================
    // For BP update (only pass-through)
    // =========================================================
    input  logic                     btb_update_valid_i,
    input  logic [ADDR_WIDTH-1:0]    btb_update_pc_i,
    input  logic [ADDR_WIDTH-1:0]    btb_update_target_i,
    input  logic                     update_is_branch_i,
    
    input  logic                     gshare_update_valid_i,
    input  logic [ADDR_WIDTH-1:0]    gshare_update_pc_i,
    input  logic                     gshare_update_taken_i
);
    // =========================================================
    // internal wires 
    // =========================================================
    logic                            gsh_taken_i, // whehter gsh predict taken or not-taken

    // =========================================================
    // Instantiate BTB 
    // =========================================================
    btb #(
        .ENTRY_NUM (BTB_ENTRY_NUM),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) btb_0 (
        .clk                 (clk),
        .reset               (reset),
        .pc_addr_i           (pc_addr_i),
        .is_branch_o         (is_branch_o),
        .btb_target_o        (target_addr_o),
        .update_valid_i      (btb_update_valid_i),
        .update_pc_i         (btb_update_pc_i),
        .update_target_i     (btb_update_target_i),
        .update_is_branch_i  (update_is_branch_i)
    );


    // ==============================================
    // Instantiate GShare Predictor
    // ==============================================
    gshare_predictor #(
        .PHT_ENTRY_NUM (PHT_ENTRY_NUM),
        .BHT_ENTRIES(BHT_ENTRIES),
        .GHR_BITS(GHR_BITS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) gsh_0 (
        .clk             (clk),
        .reset           (reset),
        .pc_addr_i       (pc_addr_i),
        .gsh_taken_o     (gsh_taken_i),
        .update_valid_i  (gshare_update_valid_i),
        .update_pc_i     (gshare_update_pc_i),
        .update_taken_i  (gshare_update_taken_i)
    );

endmodule