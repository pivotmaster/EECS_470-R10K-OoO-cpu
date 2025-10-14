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
    output logic [$clog2(DEPTH)-1:0]  disp_rob_idx_o [DISPATCH_WIDTH],

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

    // Branch flush
    output logic flush_o,
    output logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o
);

    // ========== ROB entry definition ==========
    typedef struct packed {
        logic valid;
        logic ready;
        logic exception;
        logic mispred;
        logic rd_wen;
        logic [$clog2(ARCH_REGS)-1:0]  rd_arch;
        logic [$clog2(PHYS_REGS)-1:0]  T;
        logic [$clog2(PHYS_REGS)-1:0]  Told;
    } rob_entry_t;

    rob_entry_t data [DEPTH-1:0];

    // ========== Head / Tail pointers ==========
    logic [$clog2(DEPTH)-1:0] head, tail;
    logic empty, full;

    assign empty = (head == tail) && !data[head].valid;
    assign full  = (head == tail) && data[head].valid;

    // ========== Dispatch ==========
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
            tail <= 0;
            for (int i = 0; i < DEPTH; i++) begin
                data[i].valid <= 1'b0;
            end
        end else begin
            for (int i = 0; i < DISPATCH_WIDTH; i++) begin
                if (disp_valid_i[i] && !full) begin
                    data[tail].valid     <= 1'b1;
                    data[tail].ready     <= 1'b0;
                    data[tail].rd_wen    <= disp_rd_wen_i[i];
                    data[tail].rd_arch   <= disp_rd_arch_i[i];
                    data[tail].T         <= disp_rd_new_prf_i[i];
                    data[tail].Told      <= disp_rd_old_prf_i[i];
                    data[tail].exception <= 1'b0;
                    data[tail].mispred   <= 1'b0;

                    disp_rob_idx_o[i]    <= tail;
                    disp_alloc_o[i]      <= 1'b1;
                    tail <= (tail == DEPTH-1) ? 0 : tail + 1;
                end else begin
                    disp_alloc_o[i] <= 1'b0;
                end
            end
        end
    end

    assign disp_ready_o = {!full, !full}; // same ready signal for now

    // ========== Writeback ==========
    always_ff @(posedge clk) begin
        for (int i = 0; i < WB_WIDTH; i++) begin
            if (wb_valid_i[i]) begin
                data[wb_rob_idx_i[i]].ready     <= 1'b1;
                data[wb_rob_idx_i[i]].exception <= wb_exception_i[i];
                data[wb_rob_idx_i[i]].mispred   <= wb_mispred_i[i];
            end
        end
    end

    // ========== Commit ==========
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                commit_valid_o[i] <= 1'b0;
            end
        end else begin
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                if (data[head].valid && data[head].ready && !flush_o) begin
                    commit_valid_o[i]   <= 1'b1;
                    commit_rd_wen_o[i]  <= data[head].rd_wen;
                    commit_rd_arch_o[i] <= data[head].rd_arch;
                    commit_new_prf_o[i] <= data[head].T;
                    commit_old_prf_o[i] <= data[head].Told;

                    data[head].valid <= 1'b0;
                    head <= (head == DEPTH-1) ? 0 : head + 1;
                end else begin
                    commit_valid_o[i] <= 1'b0;
                end
            end
        end
    end

    // ========== Flush ==========
    logic mispred_found;
    always_comb begin
        flush_o = 1'b0;
        flush_upto_rob_idx_o = '0;
        for (int i = 0; i < WB_WIDTH; i++) begin
            if (wb_valid_i[i] && wb_mispred_i[i] && !mispred_found) begin
                flush_o = 1'b1;
                flush_upto_rob_idx_o = wb_rob_idx_i[i];
            end
        end
    end

endmodule