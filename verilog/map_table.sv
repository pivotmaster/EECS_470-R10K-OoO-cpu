// ============================================================================
//  Module: map_table
//  Description:
//    Register Alias Table (RAT) for out-of-order CPU pipeline.
//    Performs architectural-to-physical register mapping, rename tracking,
//    and status management (valid bits, snapshot/rollback, etc.).
//
//  Typical connections:
//    - Connected to the Reorder Buffer (ROB) for commit updates and rollbacks.
//    - Connected to the Reservation Station (RS) for operand lookup.
//    - Connected to the Free List for allocating new physical registers.
//    - Connected to the Execution Units for writeback readiness tracking.
// ============================================================================

module map_table#(
    parameter int ARCH_REGS = 64,           // Number of architectural registers
    parameter int PHYS_REGS = 128,          // Number of physical registers
    parameter int DISPATCH_WIDTH = 2        // Number of instructions dispatched per cycle
)(
    input logic clk,                        // Clock signal
    input logic reset,                      // Asynchronous reset

    // =======================================================
    // ======== Lookup (for rs1, rs2) ==========================
    // =======================================================
    // Query the current mapping of source registers (rs1, rs2)
    // for each instruction being dispatched.
    //
    // Input:
    //   rs1_arch_i / rs2_arch_i : architectural source register indices
    // Output:
    //   rs1_phys_o / rs2_phys_o : mapped physical registers (tags)
    //   rs1_valid_o / rs2_valid_o : indicate if the physical register value is ready
    //
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] rs1_arch_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] rs2_arch_i,
    output logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] rs1_phys_o,
    output logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] rs2_phys_o,
    output logic                         rs1_valid_o,
    output logic                         rs2_valid_o,

    // =======================================================
    // ======== Dispatch: rename new destination reg =========
    // =======================================================
    // When new instructions are dispatched, they are assigned new
    // physical registers for their destination registers.
    //
    // Input:
    //   disp_valid_i     : per-instruction dispatch enable
    //   disp_arch_i      : architectural destination register
    //   disp_new_phys_i  : newly allocated physical register
    //
    input  logic [DISPATCH_WIDTH-1:0]                        disp_valid_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] disp_arch_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_new_phys_i,

    // =======================================================
    // ======== Writeback: mark phys reg ready ===============
    // =======================================================
    // When instructions finish execution, their destination physical
    // registers are marked as ready (value valid).
    //
    // Input:
    //   wb_valid_i : one bit per writeback slot (asserted when result is valid)
    //   wb_phys_i  : physical register written back by the corresponding instruction
    //
    input  logic [WB_WIDTH-1:0]                                          wb_valid_i,
    input  logic [WB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]                   wb_phys_i,

    // =======================================================
    // ======== Commit: restore mapping (rollback) ===========
    // =======================================================
    // At commit, the architectural map is updated with the committed
    // physical registers (synchronized with the architectural state).
    //
    // Input:
    //   commit_valid_i : indicates valid commit slot
    //   commit_arch_i  : architectural register being committed
    //   commit_phys_i  : physical register representing committed value
    //
    input  logic [COMMIT_WIDTH-1:0]                         commit_valid_i,
    input  logic [COMMIT_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]  commit_arch_i,
    input  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  commit_phys_i,

    // =======================================================
    // ======== Snapshot / Flush control =====================
    // =======================================================
    // Snapshot: Save current mapping for branch dispatch.
    // Restore: Reload previous mapping on branch misprediction or exception.
    // Flush:   Reset mappings on full pipeline flush.
    //
    // Input:
    //   flush_i             : flush the pipeline and reset table
    //   snapshot_restore_i  : restore table from saved snapshot
    //   snapshot_data_i     : snapshot data (arch_reg → phys_reg mapping)
    //
    // Output:
    //   snapshot_data_o     : current table snapshot for saving
    //
    input  logic                                              flush_i,
    input  logic                                              snapshot_restore_i,
    input  logic [$clog2(PHYS_REGS)-1:0]                     snapshot_data_i[ARCH_REGS],
    output logic [$clog2(PHYS_REGS)-1:0]                     snapshot_data_o[ARCH_REGS]
);

    // =======================================================
    // ======== Internal State ===============================
    // =======================================================
    // Each architectural register maps to a physical register entry,
    // along with a valid bit indicating whether the physical value is ready.
    //
    typedef struct packed {
        logic [$clog2(PHYS_REGS)-1:0] phys;  // physical register tag
        logic                         valid; // 1 = physical register holds valid data
    } map_entry_t;

    // Full mapping table (Architectural Register → Physical Register)
    map_entry_t table [ARCH_REGS-1:0];

endmodule