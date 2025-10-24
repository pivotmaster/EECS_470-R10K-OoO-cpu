`timescale 1ns/1ps

module dispatch_stage_tb;

    // -------------------------------------------------------
    // Parameters
    // -------------------------------------------------------
    parameter int unsigned           FETCH_WIDTH     = 2;
    parameter int unsigned           DISPATCH_WIDTH  = 2;
    parameter int unsigned           ADDR_WIDTH      = 32;

    // -------------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------------
    logic clock;
    logic reset;

    always #5 clock = ~clock;  // 10ns period

    // -------------------------------------------------------
    // DUT I/O signals
    // -------------------------------------------------------
    //Free List
    IF_ID_PACKET [FETCH_WIDTH-1:0] if_packet_i;

    logic [$clog2(DISPATCH_WIDTH+1)-1:0] free_regs_i;
    logic empty_i;
    logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] new_reg_i;
    logic [DISPATCH_WIDTH-1:0] alloc_req_o;

    //Map Table
    logic [DISPATCH_WIDTH-1:0] src1_ready_i;
    logic [DISPATCH_WIDTH-1:0] src2_ready_i;
    logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] src1_phys_i;   
    logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] src2_phys_i;  
    logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] dest_reg_old_i;

    logic [DISPATCH_WIDTH-1:0] rename_valid_o;
    logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] dest_arch_o;    
    logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] src1_arch_o;  
    logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] src2_arch_o;   

    //RS
    logic [$clog2(DISPATCH_WIDTH+1)-1:0] free_rs_slots_i;      
    logic rs_full_i;   
    
    logic [DISPATCH_WIDTH-1:0] disp_rs_valid_o;
    logic [DISPATCH_WIDTH-1:0] disp_rs_rd_wen_o;      
    rs_entry_t [DISPATCH_WIDTH-1:0] rs_packets_o; 

    //ROB
    logic [$clog2(DISPATCH_WIDTH+1)-1:0] free_rob_slots_i;  
    logic [DISPATCH_WIDTH-1:0] disp_rob_ready_i; //unused for now
    logic [DISPATCH_WIDTH-1:0][$clog2(DEPTH)-1:0] disp_rob_idx_i;   

    logic [DISPATCH_WIDTH-1:0] disp_rob_valid_o;
    logic [DISPATCH_WIDTH-1:0] disp_rob_rd_wen_o;
    //output rob_entry_t [DISPATCH_WIDTH-1:0]                           rob_packets_o,     // packets sent to rob
    logic [DISPATCH_WIDTH-1:0][$clog2(ARCH_REGS)-1:0] disp_rd_arch_o;
    logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_new_prf_o;
    logic [DISPATCH_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] disp_rd_old_prf_o;

    DISP_PACKET [DISPATCH_WIDTH-1:0] disp_packet_o;
    logic stall;
    // -------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------
    
    dispatch_stage #(
        .FETCH_WIDTH(FETCH_WIDTH),
        .DISPATCH_WIDTH(DISPATCH_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clock(clock),
        .reset(reset),

        .if_packet_i(if_packet_i),
        .free_regs_i(free_regs_i),
        .empty_i(empty_i),
        .new_reg_i(new_reg_i),
        .alloc_req_o(alloc_req_o),

        .src1_ready_i(src1_ready_i),
        .src2_ready_i(src2_ready_i),
        .src1_phys_i(src1_phys_i),
        .src2_phys_i(src2_phys_i),
        .dest_reg_old_i(dest_reg_old_i),

        .rename_valid_o(rename_valid_o),
        .dest_arch_o(dest_arch_o),
        .src1_arch_o(src1_arch_o),
        .src2_arch_o(src2_arch_o),

        .free_rs_slots_i(free_rs_slots_i),
        .rs_full_i(rs_full_i),

        .disp_rs_valid_o(disp_rs_valid_o),
        .disp_rs_rd_wen_o(disp_rs_rd_wen_o),
        .rs_packets_o(rs_packets_o),

        .free_rob_slots_i(free_rob_slots_i),
        .disp_rob_ready_i(disp_rob_ready_i), //unused for now
        .disp_rob_idx_i(disp_rob_idx_i),

        .disp_rob_valid_o(disp_rob_valid_o),
        .disp_rob_rd_wen_o(disp_rob_rd_wen_o),
        .disp_rd_arch_o(disp_rd_arch_o),
        .disp_rd_new_prf_o(disp_rd_new_prf_o),
        .disp_rd_old_prf_o(disp_rd_old_prf_o),

        .disp_packet_o(disp_packet_o),
        .stall(stall)

    );

    // -------------------------------------------------------
    // Task: Print status
    // -------------------------------------------------------
    task print_outputs(string tag);
        $display("[%0t] %s", $time, tag);

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            $display("  DISPATCH[%0d]: Free[%0d]: free_regs_num=%0d empty=%0b new_reg=%0d
            | Map[%0d]: src1_ready=%0b src2_ready=%0b src1_phys=%0d src2_phys=%0d dest_reg_old=%0d
            | RS[%0d]: free_rs_num=%0d rs_full=%0b | ROB[%0d]: free_rob_num=%0d, disp_rob_idx=%0d ",
                     i, i, free_regs_i[i], empty_i[i], new_reg_i[i], 
                     i, src1_ready_i[i], src2_ready[i], src1_phys_i[i], src2_phys_i[i], dest_reg_old_i[i],
                     i, free_rs_slots_i[i], rs_full_i[i], i, free_rob_slots_i[i], disp_rob_idx_i[i]);
        end

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            $display("  -> Free[%0d]: alloc_req=%0b | Map[%0d]: valid=%0b rd_arch=%0d r1_arch=%0d r2_arch=%0d
            | RS[%0d]: valid=%0b rs_rd_wen=%0b | ROB[%0d]: valid=%0b rob_rd_wen=%0b rd_arch=%0d T_new=%0d T_old=%0d",
                     i, alloc_req_o[i], i, rename_valid_o[i], dest_arch_o[i], src1_arch_o[i], src2_arch_o,
                     i, disp_rs_valid_o[i], disp_rs_rd_wen_o[i], i, disp_rob_valid_o[i], disp_rob_rd_wen_o[i], disp_rd_arch_o[i], disp_rd_new_prf_o[i], disp_rd_old_prf_o[i]);
        end

        $display("  stall=%0b\n", stall);

    endtask

    // -------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------
    initial begin
        $dumpfile("dispatch_stage_tb.vcd");
        $dumpvars(0, dispatch_stage_tb);

        clock = 0;
        reset = 1;

        if_packet_i = '0;
        free_regs_i = '0;
        empty_i = 0;
        new_reg_i = '0;
        alloc_req_o = '0;

        src1_ready_i = '0;
        src2_ready_i = '0;
        src1_phys_i = '0;
        src2_phys_i = '0;
        dest_reg_old_i = '0;

        free_rs_slots_i = '0;
        rs_full_i = 0;

        free_rob_slots_i = '0;
        disp_rob_ready_i = '0;
        disp_rob_idx_i = '0;

        #20;
        reset = 0;
        #10;

        // -------------------------------
        // Case 1: Normal dispatch 2 instr
        // -------------------------------
        for (int i=0;i<FETCH_WIDTH;i++) begin
            if_packet_i = '1;
        end

        free_regs_i = '1;
        empty_i = 0;
        new_reg_i[0] = 7'd31;
        new_reg_i[1] = 7'd99;

        src1_ready_i = '1;
        src2_ready_i = '1;
        src1_phys_i[0] = 7'd11;
        src1_phys_i[1] = 7'd22;
        src2_phys_i[0] = 7'd33;
        src2_phys_i[1] = 7'd44;
        dest_reg_old_i[0] = 7'd55;
        dest_reg_old_i[1] = 7'd66;

        free_rs_slots_i = '1;
        rs_full_i = 0;

        free_rob_slots_i = '1;
        disp_rob_idx_i[0] = 6'd10;
        disp_rob_idx_i[1] = 6'20;

        $finish;
    end

endmodule
