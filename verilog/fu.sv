`include "fu_if.svh"

typedef struct packed {
    logic valid;                        // issue → FU
    logic [$clog2(PHYS_REGS)-1:0] dest_prf;
    logic [$clog2(ROB_DEPTH)-1:0] rob_idx;
    logic [XLEN-1:0] src1_value;
    logic [XLEN-1:0] src2_value;
    logic [3:0] opcode;                 // operation type (ADD, SUB, etc.)
} fu_req_t;

typedef struct packed {
    logic valid;                        // FU → complete_stage
    logic [XLEN-1:0] value;
    logic [$clog2(PHYS_REGS)-1:0] dest_prf;
    logic [$clog2(ROB_DEPTH)-1:0] rob_idx;
    logic exception;
    logic mispred;
} fu_resp_t;

module fu #(
    parameter int XLEN        = 64,
    parameter int PHYS_REGS   = 128,
    parameter int ROB_DEPTH   = 64,
    parameter int ALU_COUNT   = 4,
    parameter int MUL_COUNT   = 4,
    parameter int LOAD_COUNT  = 4,
    parameter int BR_COUNT    = 4
)(
    input  logic clk,
    input  logic reset,

    // issue stage requests (flattened bus)
    input  fu_req_t  [ALU_COUNT-1:0]  alu_req,
    input  fu_req_t  [MUL_COUNT-1:0]  mul_req,
    input  fu_req_t  [LOAD_COUNT-1:0] load_req,
    input  fu_req_t  [BR_COUNT-1:0]   br_req,

    // outputs to complete stage
    output fu_resp_t [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0] fu_resp
);
    integer i;
    generate
        for (i = 0; i < ALU_COUNT; i++) begin : ALU_FU
            alu_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH))
                alu_inst (.req_i(alu_req[i]), .resp_o(fu_resp[i]));
        end

        for (i = 0; i < MUL_COUNT; i++) begin : MUL_FU
            mul_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH))
                mul_inst (.req_i(mul_req[i]), .resp_o(fu_resp[ALU_COUNT + i]));
        end

        for (i = 0; i < LOAD_COUNT; i++) begin : LOAD_FU
            load_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH))
                load_inst (.req_i(load_req[i]), .resp_o(fu_resp[ALU_COUNT + MUL_COUNT + i]));
        end

        for (i = 0; i < BR_COUNT; i++) begin : BR_FU
            branch_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH))
                br_inst (.req_i(br_req[i]), .resp_o(fu_resp[ALU_COUNT + MUL_COUNT + LOAD_COUNT + i]));
        end
    endgenerate
endmodule
