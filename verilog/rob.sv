module rob #(
    parameter int unsigned DEPTH           = 64,
    parameter int unsigned INST_W          = 16,
    parameter int unsigned DISPATCH_WIDTH  = 1,
    parameter int unsigned COMMIT_WIDTH    = 1,
    parameter int unsigned WB_WIDTH        = 4,
    parameter int unsigned ARCH_REGS       = 64,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned XLEN            = 32
)(
    input  logic clock,
    input  logic reset,

    // Dispatch
    input  logic [DISPATCH_WIDTH-1:0] disp_valid_i,
    input  logic [DISPATCH_WIDTH-1:0] disp_rd_wen_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] disp_rd_arch_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_i,
    input  logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_i,

    output logic [DISPATCH_WIDTH-1:0] disp_ready_o,
    output logic [DISPATCH_WIDTH-1:0] disp_alloc_o,
    output logic [DISPATCH_WIDTH-1:0][$clog2(DEPTH)-1:0]  disp_rob_idx_o,
    output logic [$clog2(DEPTH+1)-1:0] disp_enable_space_o, 

    // Writeback
    input  logic [WB_WIDTH-1:0] wb_valid_i,
    input  logic [WB_WIDTH-1:0][$clog2(DEPTH)-1:0] wb_rob_idx_i,
    input  logic [WB_WIDTH-1:0] wb_exception_i,
    input  logic [WB_WIDTH-1:0] wb_mispred_i,

    // Commit
    output logic [COMMIT_WIDTH-1:0] commit_valid_o,
    output logic [COMMIT_WIDTH-1:0] commit_rd_wen_o,
    output logic [COMMIT_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] commit_rd_arch_o,
    output logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] commit_new_prf_o,
    output logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] commit_old_prf_o,

    // Branch flush
    output logic flush_o,
    output logic [$clog2(DEPTH)-1:0] flush_upto_rob_idx_o
);

        // ===== ROB Entry Struct =====
    typedef struct packed {
        logic valid;
        logic ready;
        logic rd_wen;
        logic [$clog2(ARCH_REGS)-1:0] rd_arch;
        logic [$clog2(PHYS_REGS)-1:0] new_prf;
        logic [$clog2(PHYS_REGS)-1:0] old_prf;
        logic exception;
        logic mispred;
    } rob_entry_t;

    rob_entry_t rob_table [DEPTH];

    logic [$clog2(DEPTH)-1:0] head, tail;
    logic [$clog2(DEPTH):0] count;

    // ===== Internal Signals =====
    logic full, empty;
    logic [$clog2(DEPTH)-1:0] next_tail, next_head;
    logic [COMMIT_WIDTH-1:0] retire_en;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign disp_ready_o = {!full, !full};   //fixed to 2 bits

    // ===== Dispatch Logic =====
    assign disp_enable_space_o = DEPTH - count;
    always_comb begin
        next_tail = tail;
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            disp_alloc_o[i]   = 1'b0;
            disp_rob_idx_o[i] = '0;
        end

        if (!full) begin
            for (int i = 0; i < DISPATCH_WIDTH; i++) begin
                if (disp_valid_i[i] && (count + i < DEPTH)) begin
                    disp_alloc_o[i]   = 1'b1;
                    disp_rob_idx_o[i] = next_tail;
                    next_tail         = (next_tail == DEPTH-1) ? '0 : next_tail + 1;
                end
            end
        end
    end

    // ===== Commit Ready Check =====
    always_comb begin
        retire_en = '0;
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            // if (!empty && rob_table[(head + i) % DEPTH].valid && rob_table[(head + i) % DEPTH].ready && ((i == 0) || retire_en[i-1])) begin ### ?not sure the valid part
            if (!empty && rob_table[(head + i) % DEPTH].ready && ((i == 0) || retire_en[i-1])) begin
                retire_en[i] = 1'b1;
            end
        end
    end

    // ===== Sequential Block =====
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            head   <= '0;
            tail   <= '0;
            count  <= '0;
            flush_o <= 1'b0;
            flush_upto_rob_idx_o <= '0;

            for(int i = 0 ; i< COMMIT_WIDTH; i++)begin
                commit_old_prf_o[i] <= '0;
            end

            for (int i = 0; i < DEPTH; i++) begin
            //     rob_table[i].valid     <= 1'b0;
            //     rob_table[i].ready     <= 1'b0;
            //     rob_table[i].exception <= 1'b0;
            //     rob_table[i].mispred   <= 1'b0;
                rob_table[i] <= '0;
            end

        end else begin
            flush_o <= 1'b0; // default

            // ==== Writeback ====
            for (int i = 0; i < WB_WIDTH; i++) begin
                if (wb_valid_i[i]) begin
                    rob_table[wb_rob_idx_i[i]].ready     <= 1'b1;
                    rob_table[wb_rob_idx_i[i]].exception <= wb_exception_i[i];
                    rob_table[wb_rob_idx_i[i]].mispred   <= wb_mispred_i[i];
                end
            end

            // ==== Dispatch (allocate new entries) ====
            for (int i = 0; i < DISPATCH_WIDTH; i++) begin
                if (disp_alloc_o[i]) begin
                    rob_table[disp_rob_idx_o[i]].valid     <= 1'b1;
                    rob_table[disp_rob_idx_o[i]].ready     <= 1'b0;
                    rob_table[disp_rob_idx_o[i]].rd_wen    <= disp_rd_wen_i[i];
                    rob_table[disp_rob_idx_o[i]].rd_arch   <= disp_rd_arch_i[i];
                    rob_table[disp_rob_idx_o[i]].new_prf   <= disp_rd_new_prf_i[i];
                    rob_table[disp_rob_idx_o[i]].old_prf   <= disp_rd_old_prf_i[i];
                    rob_table[disp_rob_idx_o[i]].exception <= 1'b0;
                    rob_table[disp_rob_idx_o[i]].mispred   <= 1'b0;
                end
            end

            // ==== Commit (retire ready entries) ====
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                if (retire_en[i]) begin
                    commit_valid_o[i]   <= 1'b1;
                    commit_rd_wen_o[i]  <= rob_table[head + i].rd_wen;
                    commit_rd_arch_o[i] <= rob_table[head + i].rd_arch;
                    commit_new_prf_o[i] <= rob_table[head + i].new_prf;
                    commit_old_prf_o[i] <= rob_table[head + i].old_prf;

                    // Flush if mispred or exception
                    if (rob_table[head].mispred || rob_table[head].exception) begin
                        flush_o              <= 1'b1;
                        flush_upto_rob_idx_o <= head;
                        head   <= '0;//###
                        tail   <= '0;//###
                        count  <= '0;
                        for (int j = 0; j < DEPTH; j++) begin
                            rob_table[j].valid <= 1'b0;
                        end
                    end else begin
                        rob_table[head].valid <= 1'b0;
                    end
                end else begin
                    commit_valid_o[i] <= 1'b0;
                end
            end

            head <= head + $countones(retire_en);

            // ==== Update count and tail ====
            count <= count + $countones(disp_alloc_o) - $countones(retire_en);
            tail  <= next_tail;
        end

    end
    // always_ff @(negedge clock)begin
    //    // $display("head = %0d  , tail = %0d\n" , head, tail);
    //    $display("disp_rob_idx_o=%d | commit_old_prf_o: %d", disp_rob_idx_o[0], commit_old_prf_o[0]);
    // end

    // =========================================================
    // For GUI Debugger
    // =========================================================
    integer rob_trace_fd;

    initial begin
        rob_trace_fd = $fopen("dump_files/rob_trace.json", "w");
        if (rob_trace_fd == 0)
            $fatal("Failed to open dump_files/rob_trace.json!");
    end

    task automatic dump_rob_state(int cycle);
        $fwrite(rob_trace_fd, "{ \"cycle\": %0d, \"ROB\": [", cycle);
        for (int i = 0; i < DEPTH; i++) begin
            if (rob_table[i].valid) begin
                automatic rob_entry_t e = rob_table[i];
                $fwrite(rob_trace_fd,
                    "{\"idx\":%0d, \"valid\":%0d, \"ready\":%0d, \"rd_wen\":%0d,\"rd_arch\":%0d, \"new_prf\":%0d, \"old_prf\":%0d,\"exception\":%0d, \"mispred\":%0d}",
                    i, e.valid, e.ready, e.rd_wen, e.rd_arch,
                    e.new_prf, e.old_prf, e.exception, e.mispred);
            end else begin
                $fwrite(rob_trace_fd, "{\"idx\":%0d, \"valid\":0}", i);
            end

            if (i != DEPTH - 1)
                $fwrite(rob_trace_fd, ",");
        end
        $fwrite(rob_trace_fd, "]}\n");
        $fflush(rob_trace_fd); 
    endtask


    int cycle_count;
    always_ff @(posedge clock) begin
        if (reset) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            dump_rob_state(cycle_count);
        end
    end

endmodule