/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu.sv                                              //
//                                                                     //
//  Description :  Top-level module of the verisimple processor;       //
//                 This instantiates and connects the 5 stages of the  //
//                 Verisimple pipeline together.                       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"
`include "def.svh"

module cpu #(
    parameter int unsigned DISPATCH_WIDTH   = 2
)(
    input clock, // System clock
    input reset, // System reset

    input MEM_TAG   mem2proc_transaction_tag, // Memory tag for current transaction
    input MEM_BLOCK mem2proc_data,            // Data coming back from memory
    input MEM_TAG   mem2proc_data_tag,        // Tag for which transaction data is for

    output MEM_COMMAND proc2mem_command, // Command sent to memory
    output ADDR        proc2mem_addr,    // Address sent to memory
    output MEM_BLOCK   proc2mem_data,    // Data sent to memory
    output MEM_SIZE    proc2mem_size,    // Data size sent to memory

    // Note: these are assigned at the very bottom of the module
    output COMMIT_PACKET [`N-1:0] committed_insts,

    // Debug outputs: these signals are solely used for debugging in testbenches
    // Do not change for project 3
    // You should definitely change these for project 4

    // IF-stage Outputs
    output ADDR [`FETCH_WIDTH-1:0] if_NPC_dbg,
    output DATA [`FETCH_WIDTH-1:0] if_inst_dbg,
    output logic [`FETCH_WIDTH-1:0] if_valid_dbg,

    output ADDR [`FETCH_WIDTH-1:0] if_id_NPC_dbg,
    output DATA [`FETCH_WIDTH-1:0] if_id_inst_dbg,
    output logic [`FETCH_WIDTH-1:0] if_id_valid_dbg,

    //Dispatch-stage Outputs
    output ADDR [`DISPATCH_WIDTH-1:0] id_s_NPC_dbg,
    output DATA [`DISPATCH_WIDTH-1:0] id_s_inst_dbg,
    output logic [`DISPATCH_WIDTH-1:0] id_s_valid_dbg,


    output ADDR [`DISPATCH_WIDTH-1:0] s_ex_NPC_dbg,
    output DATA [`DISPATCH_WIDTH-1:0] s_ex_inst_dbg,
    output logic [`DISPATCH_WIDTH-1:0] s_ex_valid_dbg,


    //output ADDR  ex_c_NPC_dbg,
    output DATA [`DISPATCH_WIDTH-1:0] ex_c_inst_dbg
    //output logic ex_c_valid_dbg
);

    //////////////////////////////////////////////////
    //                                              //
    //                Pipeline Wires                //
    //                                              //
    //////////////////////////////////////////////////

    // Pipeline register enables
    logic if_id_enable, id_s_enable, s_ex_enable;
    logic flush;

    // From IF stage to memory
    MEM_COMMAND Imem_command; // Command sent to memory

    // I-cache
    ADDR proc2Icache_addr;
    MEM_BLOCK Icache_data_out;  //to fetch
    logic     Icache_valid_out;
    ADDR Imem_addr;


    // 2. I-Cache -> Fetch
    MEM_BLOCK [`FETCH_WIDTH-1:0] icache_to_fetch_data;

    // --- Wires for I-Cache <-> Main Memory ---
    MEM_COMMAND icache_to_mem_command; // Renamed from Imem_command
    ADDR correct_pc_target_o;

    // Outputs from IF-Stage and IF/ID Pipeline Register
    IF_ID_PACKET [`FETCH_WIDTH-1:0] if_packet, if_id_reg;

// Dispactch
    //Free list
    logic [`DISPATCH_WIDTH-1:0] alloc_req;
    // Map Table
    logic [`DISPATCH_WIDTH-1:0] rename_valid;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] dest_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] src1_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] src2_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] dest_new_prf; //T_new
    // RS
    logic [DISPATCH_WIDTH-1:0] disp_rs_valid;
    logic [`DISPATCH_WIDTH-1:0] disp_rs_rd_wen;
    rs_entry_t  [DISPATCH_WIDTH-1:0] rs_packets;
    // ROB
    logic [`DISPATCH_WIDTH-1:0] disp_rob_valid;
    logic [`DISPATCH_WIDTH-1:0] disp_rob_rd_wen;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] disp_rd_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] disp_rd_new_prf;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] disp_rd_old_prf;

// Free list
    logic [DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS-1):0] alloc_phys; // allocated PRF numbers
    logic [`DISPATCH_WIDTH-1:0] alloc_valid; // whether each alloc succeed
    logic free_full;      // true if no free regs left
    logic [$clog2(DISPATCH_WIDTH+1)-1:0] free_count; // number of free regs

// Arch map table
    logic [`ARCH_REGS-1:0][$clog2(`PHYS_REGS)-1:0] snapshot; // Full snapshot of current architectural-to-physical map
    logic restore_valid_i;  // Asserted when restoring the AMT from a saved snapshot
    logic [`ARCH_REGS-1:0][$clog2(`PHYS_REGS)-1:0] restore_snapshot_i; // Snapshot data to restore from

// CDB
    logic [`CDB_WIDTH-1:0] cdb_valid_rs;
    logic [`CDB_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] cdb_tag_rs;
    logic [`CDB_WIDTH-1:0] cdb_valid_mp;  // commit_valid_i in 'map_table.sv'
    logic [`CDB_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] cdb_phy_tag_mp;
    logic [`CDB_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] cdb_dest_arch_mp;
    //####
    logic rs_ready_i;
    logic map_ready_i;

// PRF
    //---------------- read ports (from issue stage / rename) ----------------
    logic [`READ_PORTS-1:0]rd_en;    //####
    logic [`READ_PORTS-1:0][$clog2(`PHYS_REGS)-1:0] raddr;
    logic [`READ_PORTS-1:0][`XLEN-1:0] rdata;

// ROB
    logic [`DISPATCH_WIDTH-1:0] disp_ready;
    logic [`DISPATCH_WIDTH-1:0] disp_alloc;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ROB_DEPTH)-1:0] disp_rob_idx;
    logic [$clog2(`ROB_DEPTH+1)-1:0] free_rob_slots;
    // Commit
    logic [`COMMIT_WIDTH-1:0] commit_valid;
    logic [`COMMIT_WIDTH-1:0] commit_rd_wen;
    logic [`COMMIT_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] commit_rd_arch;
    logic [`COMMIT_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] commit_new_prf;
    logic [`COMMIT_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] commit_old_prf;
    // Branch flush
    logic flush_rob;
    logic [$clog2(`ROB_DEPTH)-1:0] flush_upto_rob_idx;

// RS
    logic [$clog2(`DISPATCH_WIDTH)-1:0] rs_free_slot;      // how many slot is free? (saturate at DISPATCH_WIDTH)
    logic rs_full;
    //logic [`DISPATCH_WIDTH-1:0] disp_rs_ready; 
    rs_entry_t [`RS_DEPTH-1:0] rs_entries;
    logic [`RS_DEPTH-1:0] rs_ready;
    fu_type_e fu_types [`RS_DEPTH];   

// Map table
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] rs1_phys;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] rs2_phys;
    logic [`DISPATCH_WIDTH-1:0] rs1_ready;
    logic [`DISPATCH_WIDTH-1:0] rs2_ready;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] disp_old_phys;

    //####
    logic flush_i;
    logic snapshot_restore_i;
    logic [`ARCH_REGS-1:0][$clog2(`PHYS_REGS)-1:0] snapshot_data_i;
    logic [`ARCH_REGS-1:0][$clog2(`PHYS_REGS)-1:0] snapshot_data_o;

// Issue

    // =========================================================
    // RS -> Issue Logic
    // =========================================================

    logic [`RS_DEPTH-1:0] issue_enable; // which rs slot is going to be issued

    issue_packet_t alu_req  [`ALU_COUNT]; // pkts to ALU 
    issue_packet_t mul_req  [`MUL_COUNT];
    issue_packet_t load_req [`LOAD_COUNT];
    issue_packet_t br_req   [`BR_COUNT];

    assign rd_en = {alu_req[0].valid, alu_req[0].valid, mul_req[0].valid, mul_req[0].valid, load_req[0].valid, load_req[0].valid, br_req[0].valid, br_req[0].valid};
    assign raddr = {alu_req[0].src1_val, alu_req[0].src2_val, mul_req[0].src1_val, mul_req[0].src2_val, load_req[0].src1_val, load_req[0].src2_val, br_req[0].src1_val, br_req[0].src2_val};

// S/EX
    issue_packet_t alu_req_reg  [`ALU_COUNT]; // pkts to ALU 
    issue_packet_t mul_req_reg  [`MUL_COUNT];
    issue_packet_t load_req_reg [`LOAD_COUNT];
    issue_packet_t br_req_reg   [`BR_COUNT];


// FU
    // FU → Issue
    logic alu_ready [`ALU_COUNT];
    logic mul_ready [`MUL_COUNT];
    logic load_ready [`LOAD_COUNT];
    logic br_ready [`BR_COUNT];
    // FU responses (for debug / tracing)
    fu_resp_t fu_resp_bus [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT];
    // FU → Complete Stage (flattened)
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0] fu_valid;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0][`XLEN-1:0] fu_value;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0][$clog2(`PHYS_REGS)-1:0] fu_dest_prf;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0][$clog2(`ROB_DEPTH)-1:0] fu_rob_idx;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0] fu_exception;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0] fu_mispred;

//EX_C_REG
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0] fu_valid_reg;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0][`XLEN-1:0] fu_value_reg;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0][$clog2(`PHYS_REGS)-1:0] fu_dest_prf_reg;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0][$clog2(`ROB_DEPTH)-1:0] fu_rob_idx_reg;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0] fu_exception_reg;
    logic [`ALU_COUNT+`MUL_COUNT+`LOAD_COUNT+`BR_COUNT-1:0] fu_mispred_reg;

// Complete-stage
    // PR
    logic [`WB_WIDTH-1:0] prf_wr_en;
    logic [`WB_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] prf_waddr;
    logic [`WB_WIDTH-1:0][`XLEN-1:0] prf_wdata;
    // rob
    logic [`WB_WIDTH-1:0] wb_valid;
    logic [`WB_WIDTH-1:0][$clog2(`ROB_DEPTH)-1:0] wb_rob_idx;
    logic [`WB_WIDTH-1:0] wb_exception;
    logic [`WB_WIDTH-1:0] wb_mispred;
    cdb_entry_t [`CDB_WIDTH-1:0] cdb_packets;

// Retire-stage
    // arch. map
    logic [`COMMIT_WIDTH-1:0] amt_commit_valid;
    logic [`COMMIT_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] amt_commit_arch;
    logic [`COMMIT_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] amt_commit_phys;
    // free list
    logic [`COMMIT_WIDTH-1:0] free_valid;
    logic [`COMMIT_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] free_phys;
    // debug in cpu
    logic [$clog2(`COMMIT_WIDTH+1)-1:0] retire_cnt;

//
    // Outputs from ID stage and ID/S Pipeline Register
    DISP_PACKET [`DISPATCH_WIDTH-1:0] disp_packet, id_s_reg;
    logic stall;

    // Outputs from Issue stage and S/EX Pipeline Register
    DISP_PACKET [`DISPATCH_WIDTH-1:0] issue_packet, s_ex_reg;

    // Outputs from EX-Stage and EX/C Pipeline Register
    EX_MEM_PACKET [`DISPATCH_WIDTH-1:0] ex_packet, ex_c_reg;

    // Outputs from C-Stage and MEM/WB Pipeline Register
    MEM_WB_PACKET mem_packet, mem_wb_reg;

    // Outputs from MEM-Stage to memory
    ADDR        Dmem_addr;
    MEM_BLOCK   Dmem_store_data;
    MEM_COMMAND Dmem_command;
    MEM_SIZE    Dmem_size;

    // Outputs from WB-Stage (These loop back to the register file in ID)
    COMMIT_PACKET wb_packet;

    // Logic for stalling memory stage
    logic       new_load;
    logic       mem_tag_match;
    logic       rd_mem_q;       // previous load
    MEM_TAG     outstanding_mem_tag;    // tag load is waiting in
    MEM_COMMAND Dmem_command_filtered;  // removes redundant loads

    //////////////////////////////////////////////////
    //                                              //
    //                Memory Outputs                //
    //                                              //
    //////////////////////////////////////////////////

    // these signals go to and from the processor and memory
    // we give precedence to the mem stage over instruction fetch
    // note that there is no latency in project 3
    // but there will be a 100ns latency in project 4

    always_comb begin
        if (Dmem_command != MEM_NONE) begin  // read or write DATA from memory
            proc2mem_command = Dmem_command_filtered;
            proc2mem_size    = Dmem_size;
            proc2mem_addr    = Dmem_addr;
        end else begin                      // read an INSTRUCTION from memory
            proc2mem_command = Imem_command;
            proc2mem_addr    = Imem_addr;
            proc2mem_size    = DOUBLE;      // instructions load a full memory line (64 bits)
        end
        proc2mem_data = Dmem_store_data;
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  Valid Bit                   //
    //                                              //
    //////////////////////////////////////////////////

    // This state controls the stall signal that artificially forces IF
    // to stall until the previous instruction has completed.
    // For project 3, start by assigning if_valid to always be 1

    logic if_valid, if_flush;
    logic pred_valid_i, pred_taken_i;
    logic [$clog2(`FETCH_WIDTH)-1:0] pred_lane_i;   // which instruction is branch    
    ADDR pred_target_i; // predicted target PC Addr


    // valid bit will cycle through the pipeline and come back from the wb stage
    assign if_valid = !stall;


    //////////////////////////////////////////////////
    //                                              //
    //                  I-cache                     //
    //                                              //
    //////////////////////////////////////////////////
    icache icache_0(
        .clock (clock),
        .reset (reset),

        // Inputs

        // From memory
        .Imem2proc_transaction_tag(mem2proc_transaction_tag), 
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_data_tag(mem2proc_data_tag),

        // From fetch stage
        .proc2Icache_addr(proc2Icache_addr),

        // Outputs
        // To memory
        .proc2Imem_command(Imem_command),
        .proc2Imem_addr(Imem_addr),


        .Icache_data_out(Icache_data_out),
        .Icache_valid_out(Icache_valid_out) // When valid is high
    );

    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////


    stage_if stage_if_0(
        .clock (clock),
        .reset (reset),

        // Inputs
        .if_valid (if_valid),
        .if_flush (if_flush),       

        .pred_valid_i(pred_valid_i),     
        .pred_lane_i(pred_lane_i),      
        .pred_taken_i(pred_taken_i),     
        .pred_target_i(pred_target_i),    

        // =========================================================
        // Fetch <-> ICache / Mem
        // =========================================================
        .Imem_data (icache_to_fetch_data),

        .Imem2proc_transaction_tag (mem2proc_transaction_tag),
        .Imem2proc_data_tag (mem2proc_data_tag),

        // Outputs
        // These now go to the I-Cache, NOT main memory
        .Imem_command (icache_to_mem_command),  // <-- MODIFIED (Was: Imem_command)
        .Imem_addr (proc2Icache_addr), 

        .correct_pc_target_o(correct_pc_target_o), 
        .if_packet_o (if_packet)
    );

    // IF-stage debug outputs
    always_comb begin
		for(int i=0;i<`FETCH_WIDTH;i++)begin
			if_NPC_dbg[i] = if_packet[i].NPC;
			if_inst_dbg[i] = if_packet[i].inst;
			if_valid_dbg[i] = if_packet[i].valid;
		end
	end

    //////////////////////////////////////////////////
    //                                              //
    //            IF/ID Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

    assign if_id_enable = !stall;

    always_ff @(posedge clock) begin
        if (reset) begin
            for(int i=0;i<`FETCH_WIDTH;i++) begin
                if_id_reg[i].inst  <= `NOP;
                if_id_reg[i].valid <= `FALSE;
                if_id_reg[i].NPC   <= 0;
                if_id_reg[i].PC    <= 0;
            end
        end else if (if_id_enable) begin
            for(int i=0;i<`FETCH_WIDTH;i++) begin
                if_id_reg[i] <= if_packet[i];
            end
        end
    end

    // debug outputs
    always_comb begin
		for(int i=0;i<`FETCH_WIDTH;i++) begin
			if_id_NPC_dbg[i] = if_id_reg[i].NPC;
			if_id_inst_dbg[i] = if_id_reg[i].inst;
			if_id_valid_dbg[i] = if_id_reg[i].valid;
		end
	end

    //////////////////////////////////////////////////
    //                                              //
    //               Dispatch-Stage                 //
    //                                              //
    //////////////////////////////////////////////////

    dispatch_stage dispatch_stage_0(
        .clock (clock),
        .reset (reset),

        .if_packet_i(if_id_reg),
        //free list inputs
        .free_regs_i(free_count),
        .free_full_i(free_full),
        .new_reg_i(alloc_phys),

        //free list outputs
        .alloc_req_o(alloc_req),

        //map table inputs
        .src1_ready_i(rs1_ready),
        .src2_ready_i(rs2_ready),
        .src1_phys_i(rs1_phys),
        .src2_phys_i(rs2_phys),
        .dest_reg_old_i(disp_old_phys),

        //map table outputs
        .rename_valid_o(rename_valid),
        .dest_arch_o(dest_arch),
        .src1_arch_o(src1_arch),
        .src2_arch_o(src2_arch),
        .dest_new_prf(dest_new_prf),

        //rs inputs
        .free_rs_slots_i(rs_free_slot),
        .rs_full_i(rs_full),

        //rs outputs
        .disp_rs_valid_o(disp_rs_valid),
        .disp_rs_rd_wen_o(disp_rs_rd_wen),
        .rs_packets_o(rs_packets),

        //rob inputs
        .free_rob_slots_i(free_rob_slots),
        .disp_rob_ready_i(disp_ready),
        .disp_rob_idx_i(disp_rob_idx),

        //rob outputs
        .disp_rob_valid_o(disp_rob_valid),
        .disp_rob_rd_wen_o(disp_rob_rd_wen),
        .disp_rd_arch_o(disp_rd_arch),
        .disp_rd_new_prf_o(disp_rd_new_prf),
        .disp_rd_old_prf_o(disp_rd_old_prf),

        .disp_packet_o(disp_packet),
        .stall(stall)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                    ROB                       //
    //                                              //
    //////////////////////////////////////////////////

    rob rob_0(
        .clock(clock),
        .reset(reset),

        // Dispatch
        .disp_valid_i(disp_rob_valid),
        .disp_rd_wen_i(disp_rob_rd_wen),
        .disp_rd_arch_i(disp_rd_arch),
        .disp_rd_new_prf_i(disp_rd_new_prf),
        .disp_rd_old_prf_i(disp_rd_old_prf),

        .disp_ready_o(disp_ready),
        .disp_alloc_o(disp_alloc),
        .disp_rob_idx_o(disp_rob_idx),
        .disp_enable_space_o(free_rob_slots),

        // Writeback
        .wb_valid_i(wb_valid),
        .wb_rob_idx_i(wb_rob_idx),
        .wb_exception_i(wb_exception),
        .wb_mispred_i(wb_exception),

        // Commit
        .commit_valid_o(commit_valid),
        .commit_rd_wen_o(commit_rd_wen),
        .commit_rd_arch_o(commit_rd_arch),
        .commit_new_prf_o(commit_new_prf),
        .commit_old_prf_o(commit_old_prf),

        // Branch flush
        .flush_o(flush_rob),
        .flush_upto_rob_idx_o(flush_upto_rob_idx)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                  map table                   //
    //                                              //
    //////////////////////////////////////////////////

    map_table map_table_0(
        .clock(clock),
        .reset(reset),

        .rs1_arch_i(src1_arch),
        .rs2_arch_i(src2_arch),

        .rs1_phys_o(rs1_phys),
        .rs2_phys_o(rs2_phys),
        .rs1_valid_o(rs1_ready),
        .rs2_valid_o(rs2_ready),

        .disp_valid_i(rename_valid),
        .disp_arch_i(dest_arch),
        .disp_new_phys_i(dest_new_prf),
        .disp_old_phys_o(disp_old_phys),


        .wb_valid_i(cdb_valid_mp),//
        .wb_phys_i(cdb_phy_tag_mp),//
        //####
        .flush_i(flush_i),
        .snapshot_restore_i(snapshot_restore_i),
        .snapshot_data_i(snapshot_data_i),
        .snapshot_data_o(snapshot_data_o)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                 free list                    //
    //                                              //
    //////////////////////////////////////////////////

    free_list free_list_0(
        .clock(clock),
        .reset(reset),
        //Inputs
        .alloc_req_i(alloc_req),

        .free_valid_i(free_valid),
        .free_phys_i(free_phys), 

        //Outputs
        .alloc_phys_o(alloc_phys), // allocated PRF numbers
        .alloc_valid_o(alloc_valid),
        .full_o(free_full),
        .free_count_o(free_count)
    );

    //////////////////////////////////////////////////
    //                                              //
    //            physical register file            //
    //                                              //
    //////////////////////////////////////////////////

    pr pr_0(
        .clock (clock),
        .reset (reset),
        //Inputs    
        .rd_en(rd_en),
        .raddr(raddr),
        .wr_en(prf_wr_en), 
        .waddr(prf_waddr),
        .wdata(prf_wdata),
        //Output
        .rdata_o(rdata)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                  Arch map                    //
    //                                              //
    //////////////////////////////////////////////////

    arch_map_table arch_map_table_0(
        .clock (clock),
        .reset (reset),

        //Inputs
        .commit_valid_i(amt_commit_valid),  // One bit per commit slot; high = valid commit
        .commit_arch_i(amt_commit_arch),   // Architectural register(s) being committed
        .commit_phys_i(amt_commit_phys),   // Physical register(s) now representing committed state
        //####
        .restore_valid_i(restore_valid_i),  // Asserted when restoring the AMT from a saved snapshot
        .restore_snapshot_i(restore_snapshot_i), // Snapshot data to restore from

        //Output
        .snapshot_o(snapshot) // Full snapshot of current architectural-to-physical map
    );

    //////////////////////////////////////////////////
    //                                              //
    //                    CDB                       //
    //                                              //
    //////////////////////////////////////////////////

    cdb cdb_0(
        .clock (clock),
        .reset (reset),

        //Inputs
        .cdb_packets_i(cdb_packets),

        .rs_ready_i(rs_ready_i),    //####
        .map_ready_i(map_ready_i),  //####

        //Outputs
        .cdb_valid_rs_o(cdb_valid_rs), 
        .cdb_tag_rs_o(cdb_tag_rs),
 
        .cdb_valid_mp_o(cdb_valid_mp),  // commit_valid_i in 'map_table.sv'
        .cdb_phy_tag_mp_o(cdb_phy_tag_mp),
        .cdb_dest_arch_mp_o(cdb_dest_arch_mp)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                    RS                        //
    //                                              //
    //////////////////////////////////////////////////

    RS rs_0(
        .clock (clock),
        .reset (reset),
        .flush(flush),
        //Inputs
        .disp_valid_i(disp_rs_valid),
        .rs_packets_i(rs_packets),
        .disp_rs_rd_wen_i(disp_rs_rd_wen),

        .cdb_valid_i(cdb_valid_rs),
        .cdb_tag_i(cdb_tag_rs),

        .issue_enable_i(issue_enable),
        
        //Outputs
        .free_slots_o(rs_free_slot),
        .rs_full_o(rs_full),
        //.disp_rs_ready_o(disp_rs_ready),

        .rs_entries_o(rs_entries),
        .rs_ready_o(rs_ready),  
        .fu_type_o(fu_types)
    );

    //////////////////////////////////////////////////
    //                                              //
    //            ID/S Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

    assign id_s_enable = !stall;

    always_ff @(posedge clock) begin
        if (reset) begin
            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			    id_s_reg[i] <= '0;
		    end
        end else if (id_s_enable) begin
            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			    id_s_reg[i] <= disp_packet[i];
		    end
        end
    end


    // debug outputs
    always_comb begin
		for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			id_s_NPC_dbg[i] = id_s_reg[i].NPC;
			id_s_inst_dbg[i] = id_s_reg[i].inst;
			id_s_valid_dbg[i] = id_s_reg[i].valid;
		end
	end

    //////////////////////////////////////////////////
    //                                              //
    //                Issue-Stage                   //
    //                                              //
    //////////////////////////////////////////////////
    issue_logic issue_0(
        .clock(clock),
        .reset(reset),
        // Inputs
        .rs_entries_i(rs_entries),
        .rs_ready_i(rs_ready),
        .fu_types_i(fu_types),

        .issue_enable_o(issue_enable), // which rs slot is going to be issued
        .alu_ready_i(alu_ready),
        .mul_ready_i(mul_ready),
        .load_ready_i(load_ready),
        .br_ready_i(br_ready),

        .alu_req_o(alu_req), // pkts to ALU 
        .mul_req_o(mul_req),
        .load_req_o(load_req),
        .br_req_o(br_req)
    );


    //////////////////////////////////////////////////
    //                                              //
    //            S/EX Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////
    assign s_ex_enable = !stall;

    always_ff @(posedge clock) begin
        if (reset) begin
            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			    s_ex_reg[i] <= '0;
		    end
        end else if (s_ex_enable) begin
            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			    s_ex_reg[i] <= issue_packet[i];
		    end
            alu_req_reg[0].valid <= alu_req[0].valid;
            alu_req_reg[0].rob_idx <= alu_req[0].rob_idx;
            alu_req_reg[0].imm <= alu_req[0].imm;
            alu_req_reg[0].fu_type <= alu_req[0].fu_type;
            alu_req_reg[0].opcode <= alu_req[0].opcode;
            alu_req_reg[0].dest_tag <= alu_req[0].dest_tag;
            
            mul_req_reg[0].valid <= mul_req[0].valid;
            mul_req_reg[0].rob_idx <= mul_req[0].rob_idx;
            mul_req_reg[0].imm <= mul_req[0].imm;
            mul_req_reg[0].fu_type <= mul_req[0].fu_type;
            mul_req_reg[0].opcode <= mul_req[0].opcode;
            mul_req_reg[0].dest_tag <= mul_req[0].dest_tag;

            load_req_reg[0].valid <= load_req[0].valid;
            load_req_reg[0].rob_idx <= load_req[0].rob_idx;
            load_req_reg[0].imm <= load_req[0].imm;
            load_req_reg[0].fu_type <= load_req[0].fu_type;
            load_req_reg[0].opcode <= load_req[0].opcode;
            load_req_reg[0].dest_tag <= load_req[0].dest_tag;

            br_req_reg[0].valid <= br_req[0].valid; 
            br_req_reg[0].rob_idx <= br_req[0].rob_idx;
            br_req_reg[0].imm <= br_req[0].imm;
            br_req_reg[0].fu_type <= br_req[0].fu_type;
            br_req_reg[0].opcode <= br_req[0].opcode;
            br_req_reg[0].dest_tag <= br_req[0].dest_tag;
        end
    end

    // debug outputs
    always_comb begin
		for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			s_ex_NPC_dbg[i] = s_ex_reg[i].NPC;
			s_ex_inst_dbg[i] = s_ex_reg[i].inst;
			s_ex_valid_dbg[i] = s_ex_reg[i].valid;
		end
	end

    //////////////////////////////////////////////////
    //                                              //
    //                     FU                       //
    //                                              //
    //////////////////////////////////////////////////
    assign {alu_req_reg[0].src1_val, alu_req_reg[0].src2_val, mul_req_reg[0].src1_val, mul_req_reg[0].src2_val, load_req_reg[0].src1_val, load_req_reg[0].src2_val, br_req_reg[0].src1_val, br_req_reg[0].src2_val} = rdata;
    fu fu_0(
        //Inputs
        .alu_req(alu_req_reg),
        .mul_req(mul_req_reg),
        .load_req(load_req_reg),
        .br_req(br_req_reg),

        //Outputs
        .alu_ready_o(alu_ready),
        .mul_ready_o(mul_ready),
        .load_ready_o(load_ready),
        .br_ready_o(br_ready),

        .fu_resp_bus(fu_resp_bus),

        .fu_valid_o(fu_valid),
        .fu_value_o(fu_value),
        .fu_dest_prf_o(fu_dest_prf),
        .fu_rob_idx_o(fu_rob_idx),
        .fu_exception_o(fu_exception),
        .fu_mispred_o(fu_mispred)
    );

    //////////////////////////////////////////////////
    //                                              //
    //             EX/C Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

    always_ff @(posedge clock) begin
        if (reset) begin
            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
                ex_c_inst_dbg <= `NOP; // debug output
                ex_c_reg      <= 0;    // the defaults can all be zero!
            end
        end else begin
            fu_valid_reg <= fu_valid;
            fu_value_reg <= fu_value;
            fu_dest_prf_reg <= fu_dest_prf;
            fu_rob_idx_reg <= fu_rob_idx;
            fu_exception_reg <= fu_exception;
            fu_mispred_reg <= fu_mispred;;

            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
                ex_c_inst_dbg[i] <= s_ex_inst_dbg[i]; // debug output, just forwarded from ID
                ex_c_reg[i] <= ex_packet[i];
            end
        end
    end

    // debug outputs
    //assign ex_c_NPC_dbg   = ex_c_reg.NPC;

    //////////////////////////////////////////////////
    //                                              //
    //                Complete-Stage                //
    //                                              //
    //////////////////////////////////////////////////

    complete_stage complete_stage0(
        .clock(clock),
        .reset(reset),

        // FU
        .fu_valid_i(fu_valid_reg),
        .fu_value_i(fu_value_reg),
        .fu_dest_prf_i(fu_dest_prf_reg),
        .fu_rob_idx_i(fu_rob_idx_reg),
        .fu_exception_i(fu_exception_reg),
        .fu_mispred_i(fu_mispred_reg),

        // PR
        .prf_wr_en_o(prf_wr_en),
        .prf_waddr_o(prf_waddr),
        .prf_wdata_o(prf_wdata),

        // rob
        .wb_valid_o(wb_valid),
        .wb_rob_idx_o(wb_rob_idx),
        .wb_exception_o(wb_exception),
        .wb_mispred_o(wb_mispred),

        // cdb
        .cdb_o(cdb_packets)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                  retire                      //
    //                                              //
    //////////////////////////////////////////////////

    retire_stage retire_stage_0(
        .clock(clock),
        .reset(reset),

        // rob
        .commit_valid_i(commit_valid),
        .commit_rd_wen_i(commit_rd_wen),
        .commit_rd_arch_i(commit_rd_arch),
        .commit_new_prf_i(commit_new_prf),
        .commit_old_prf_i(commit_old_prf),
        .flush_i(flush_rob),

        // arch. map
        .amt_commit_valid_o(amt_commit_valid),
        .amt_commit_arch_o(amt_commit_arch),
        .amt_commit_phys_o(amt_commit_phys),

        // free list
        .free_valid_o(free_valid),
        .free_reg_o(free_phys),
        .retire_cnt_o(retire_cnt)
    );

    // New address if:
    // 1) Previous instruction wasn't a load
    // 2) Load address changed
    logic valid_load;
    //assign valid_load = ex_mem_reg.valid && ex_mem_reg.rd_mem; 
    assign new_load = valid_load && !rd_mem_q;

    assign mem_tag_match = outstanding_mem_tag == mem2proc_data_tag;

//    assign Dmem_command_filtered = new_load || ex_mem_reg.wr_mem ? Dmem_command : MEM_NONE;

    always_ff @(posedge clock) begin
        if (reset) begin
            rd_mem_q            <= 1'b0;
            outstanding_mem_tag <= '0;
        end else begin
            rd_mem_q            <= valid_load;
            outstanding_mem_tag <= new_load      ? mem2proc_transaction_tag : 
                                   mem_tag_match ? '0 : outstanding_mem_tag;
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //               Pipeline Outputs               //
    //                                              //
    //////////////////////////////////////////////////

    // Output the committed instruction to the testbench for counting
    assign committed_insts[0] = wb_packet;

endmodule // pipeline
