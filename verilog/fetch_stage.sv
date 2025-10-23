/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  fetch_stage.sv                                      //
//                                                                     //
//  Description :  instruction fetch (IF) stage of the pipeline;       //
//                 fetch instruction, compute next PC location, and    //
//                 send them down the pipeline.                        //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "defs.svh"

module stage_if #(
    parameter int unsigned           FETCH_WIDTH  = 2,
    parameter int unsigned           ADDR_WIDTH   = 32

)(
    input logic                            clock,          // system clock
    input logic                            reset,          // system reset
    input logic                            if_valid,       // only go to next PC when true (stall)
    input logic                            if_flush,       

    // =========================================================
    // Branch Predictor ->  Fetch (only first branch was computed!!)
    // =========================================================
    input  logic                           pred_valid_i,     
    input  logic [$clog2(FETCH_WIDTH)-1:0] pred_lane_i,      // which instruction is branch
    input  logic                           pred_taken_i,     
    input  logic [ADDR_WIDTH-1:0]          pred_target_i,    // predicted target PC Addr

    // =========================================================
    // Fetch <-> ICache / Mem (get instructions)
    // Problem : fetch one line (from ICache) per cycle (might not enough for N-way)
    // Possible Solution: dual-line fetch (two fetch requests per cycle)?
    // =========================================================
    input  MEM_BLOCK [FETCH_WIDTH-1:0]     Imem_data,      // data coming back from Instruction memory
    input  MEM_TAG                         Imem2proc_transaction_tag,        // Should be zero unless there is a response
    input  MEM_TAG                         Imem2proc_data_tag,
    output MEM_COMMAND                     Imem_command, // Command sent to memory
    output ADDR                            Imem_addr // address sent to Instruction memory

    // =========================================================
    // EXE -> Fetch (real branch result)
    // =========================================================
    input logic [ADDR_WIDTH-1:0]           correct_pc_target_o, //exe stage will compute the correct target for branch instruction

    // =========================================================
    // Fetch -> Dispatch 
    // =========================================================
    output IF_ID_PACKET [FETCH_WIDTH-1:0]  if_packet_o,
    
);

endmodule