/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  free_list.sv                                        //
//                                                                     //
//  Description : 
//  - Free List for R10K-like OoO Processor
//  - Keeps track of available physical registers
//  - Supports simultaneous allocation (dispatch) and release (commit)
//  - Release-first policy (commit reg becomes available same cycle)
//                                                                     //
/////////////////////////////////////////////////////////////////////////

module free_list #(
    parameter int unsigned DISPATCH_WIDTH  = 2,
    parameter int unsigned COMMIT_WIDTH    = 2,
    parameter int unsigned ARCH_REGS       = 64,
    parameter int unsigned PHYS_REGS       = 128
)(
    input  logic clk,
    input  logic reset,

    // =========================================================
    // Dispatch <-> free list: allocate new physical registers
    // =========================================================
    input  logic [DISPATCH_WIDTH-1:0]                        alloc_req_i,  // requests new PRF
    output logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS-1):0] alloc_phys_o, // allocated PRF numbers
    output logic [DISPATCH_WIDTH-1:0]                        alloc_valid_o, // whether each alloc succeed
    output logic                                             full_o,       // true if no free regs left
    output logic [$clog2(PHYS_REGS):0]                       free_count_o, // number of free regs
    // output logic [DISPATCH_WIDTH-1:0]                       new_reg_o,
    // output logic [$clog2(DISPATCH_WIDTH)-1:0]               free_regs_o,   // how many regsiters are free? (saturate at DISPATCH_WIDTH)
    // output logic                                            empty_o,

    // =========================================================
    // Commit -> free list: release old physical registers
    // =========================================================
    input  logic [COMMIT_WIDTH-1:0]                         free_valid_i,  //not all instructions will release reg (ex:store)
    input  logic [COMMIT_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  free_phys_i,     
);

    // =========================================================
    // Internal storage for free registers
    // =========================================================
    logic [$clog2(PHYS_REGS)-1:0] free_fifo [PHYS_REGS-1:0];
    logic [$clog[PHYS_REGS]:0]head, tail, count;

    assign free_count_o = count;
    assign full_o = (count < DISPATCH_WIDTH);

    // =========================================================
    // Initialize free list
    // =========================================================
    always_ff @(posedge clk or posedge reset ) begin
        if (reset) begin
            head  <= 0;
            tail  <= PHYS_REGS - ARCH_REGS;
            count <= PHYS_REGS - ARCH_REGS;
            for (int i = 0 ; i < PHYS_REGS; i++)begin
                free_fifo[i] <= i + ARCH_REGS; 
            end
            for (int i =0 ; i< DISPATCH_WIDTH ; i++)begin
                alloc_phys_o[i] <= '0;
                alloc_valid_o[i] <= 1'b0;
            end
        end else begin
            // =========================================================
            //  Release (Commit) — push freed physical regs back
            // =========================================================
            for (int j = 0; j < COMMIT_WIDTH; j++) begin
                if (free_valid_i[j]) begin
                    free_fifo[tail] <= free_phys_i[j];
                    tail  <= (tail + 1) % PHYS_REGS;
                    count <= count + 1;
                end
            end

            // =====================================================
            // Allocation (Dispatch)
            // =====================================================
            for(int i = 0; i < DISPATCH_WIDTH ; i++)begin
                if(alloc_req_i[i] && (count > 0))begin
                    alloc_phys_o[i] <= free_fifo[head];
                    alloc_valid_o[i] <= 1'b1;
                    head <= (head+1) % PHYS_REGS;
                    count <= count -1 ; 
                end
                else begin
                    alloc_phys_o[i] <= '0;
                    alloc_valid_o[i] <= 1'b0;
                end
            end
        end
    end 

endmodule