module ROB #(
    parameter int unsigned DEPTH           = 64,
    parameter int unsigned INST_W          = 16,
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned COMMIT_WIDTH    = 2,
    parameter int unsigned WB_WIDTH        = 4,
    parameter int unsigned ARCH_REGS       = 64,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned XLEN            = 64
)(
    input  logic clk,
    input  logic rst_n,

    // Dispatch
    input  logic [DISPATCH_WIDTH-1:0] disp_valid_i,
    input  logic [DISPATCH_WIDTH-1:0] disp_rd_wen_i,
    input  logic [$clog2(ARCH_REGS)-1:0] disp_rd_arch_i [DISPATCH_WIDTH],
    input  logic [$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i [DISPATCH_WIDTH],
    input  logic [$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i [DISPATCH_WIDTH],

    output logic [DISPATCH_WIDTH-1:0] disp_ready_o,
    output logic [DISPATCH_WIDTH-1:0] disp_alloc_o,
    output logic [$clog2(DEPTH)-1:0] disp_rob_idx_o [DISPATCH_WIDTH],

    // Writeback
    input  logic [WB_WIDTH-1:0] wb_valid_i,
    input  logic [$clog2(DEPTH)-1:0] wb_rob_idx_i [WB_WIDTH],
    input  logic [WB_WIDTH-1:0] wb_exception_i,
    input  logic [WB_WIDTH-1:0] wb_mispred_i,

    // Commit
    output logic [COMMIT_WIDTH-1:0] commit_valid_o,
    output logic [COMMIT_WIDTH-1:0] commit_rd_wen_o,
    output logic [$clog2(ARCH_REGS)-1:0] commit_rd_arch_o [COMMIT_WIDTH],
    output logic [$clog2(PHYS_REGS)-1:0] commit_new_prf_o [COMMIT_WIDTH],
    output logic [$clog2(PHYS_REGS)-1:0] commit_old_prf_o [COMMIT_WIDTH],

    // Branch
    output logic flush_o,
    output logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o
);
    typedef struct packed {
        logic valid;
        logic ready;
        logic exception;
        logic mispred;
        logic rd_wen;
        logic [INST_W-1:0] inst;
        logic [$clog2(PHYS_REGS)-1:0] T;
        logic [$clog2(PHYS_REGS)-1:0] Told;
    } unit;
    unit [DEPTH-1:0] data;
    logic [$clog2(DEPTH)-1:0] head, tail, next_head, next_tail;
    logic empty, full;

endmodule
