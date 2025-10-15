module map_table#(
    parameter int ARCH_REGS = 64,
    parameter int PHYS_REGS = 128,
    parameter int DISPATCH_WIDTH = 2
)(
    input logic clk,
    input logic reset,

    // =======================================================
    // ======== Lookup (for rs1, rs2) ==========================
    // =======================================================
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] rs1_arch_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] rs2_arch_i,
    output logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] rs1_phys_o,
    output logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] rs2_phys_o,
    output logic                         rs1_valid_o,
    output logic                         rs2_valid_o,

    // =======================================================
    // ======== Dispatch: rename new destination reg =========
    // =======================================================
    input  logic [DISPATCH_WIDTH-1:0]                        disp_valid_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] disp_arch_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_new_phys_i,

    // =======================================================
    // ======== Writeback: mark phys reg ready ===============
    // =======================================================
    input  logic [WB_WIDTH-1:0]                                          wb_valid_i,
    input  logic [WB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]                   wb_phys_i,

    // =======================================================
    // ======== Commit: restore mapping (rollback) ===========
    // =======================================================
    input  logic [COMMIT_WIDTH-1:0]                         commit_valid_i,
    input  logic [COMMIT_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]  commit_arch_i,
    input  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  commit_phys_i,
    // =======================================================
    // ======== Snapshot / Flush control =====================
    // =======================================================
    input  logic                                              flush_i,           // flush pipeline
    input  logic                                              snapshot_restore_i,// restore snapshot
    input  logic [$clog2(PHYS_REGS)-1:0]                     snapshot_data_i[ARCH_REGS],
    output logic [$clog2(PHYS_REGS)-1:0]                     snapshot_data_o[ARCH_REGS]
);

    // =======================================================
    // ======== Internal state ===============================
    // =======================================================
    typedef struct packed {
        logic [$clog2(PHYS_REGS)-1:0] phys;  // current physical reg (tag)
        logic                         valid; // whether phys reg value ready
    } map_entry_t;

    map_entry_t table [ARCH_REGS-1:0];
endmodule