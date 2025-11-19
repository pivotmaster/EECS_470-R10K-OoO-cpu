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
    parameter int unsigned DISPATCH_WIDTH   = 1
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
    assign icache_to_fetch_data[0] = Icache_data_out;

    // --- Wires for I-Cache <-> Main Memory ---
    MEM_COMMAND icache_to_mem_command; // Renamed from Imem_command
    ADDR correct_pc_target_o;

    // Outputs from IF-Stage and IF/ID Pipeline Register
    IF_ID_PACKET [`FETCH_WIDTH-1:0] if_packet, if_id_reg;
// Fetch
    logic take_branch;
// Dispactch
    //Free list
    logic [`DISPATCH_WIDTH-1:0] disp_free_space;
    logic [`DISPATCH_WIDTH-1:0] alloc_req;
    // Map Table
    logic [`DISPATCH_WIDTH-1:0] rename_valid;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] dest_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] src1_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] src2_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] dest_new_prf; //T_new
    logic [`DISPATCH_WIDTH-1:0] is_branch; //### 11/10 sychenn ###//
    
    // RS
    logic [`DISPATCH_WIDTH-1:0] disp_rs_valid;
    logic [`DISPATCH_WIDTH-1:0] disp_rs_rd_wen;
    rs_entry_t  [`DISPATCH_WIDTH-1:0] rs_packets;
    // ROB
    logic [`DISPATCH_WIDTH-1:0] disp_rob_space;
    logic [`DISPATCH_WIDTH-1:0] disp_rob_valid;
    logic [`DISPATCH_WIDTH-1:0] disp_rob_rd_wen;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`ARCH_REGS)-1:0] disp_rd_arch;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] disp_rd_new_prf;
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] disp_rd_old_prf;


// Free list
    logic [`DISPATCH_WIDTH-1:0][$clog2(`PHYS_REGS)-1:0] alloc_phys; // allocated PRF numbers
    logic [`DISPATCH_WIDTH-1:0] alloc_valid; // whether each alloc succeed
    logic free_full;      // true if no free regs left
    logic [$clog2(`PHYS_REGS+1)-1:0] free_count; // number of free regs

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

     //### TODO: for debug only (sychenn 11/6) ###//
    logic flush_rob_debug;
    logic [`ROB_DEPTH-1:0] flush_free_regs_valid;
    logic [`PHYS_REGS-1:0] flush_free_regs;


// RS
    logic [$clog2(`DISPATCH_WIDTH+1)-1:0] rs_free_slot;      // how many slot is free? (saturate at DISPATCH_WIDTH)
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
    map_entry_t      snapshot_data_i [`ARCH_REGS-1:0];
    map_entry_t       snapshot_data_o [`ARCH_REGS-1:0] ;
    map_entry_t       snapshot_reg [`ARCH_REGS-1:0];
    logic checkpoint_valid;//### 11/10 sychenn ###//
    logic has_snapshot; // guard restore until a snapshot is captured

// Issue

    // =========================================================
    // RS -> Issue Logic
    // =========================================================

    logic [`RS_DEPTH-1:0] issue_enable ; // which rs slot is going to be issued

    issue_packet_t alu_req  [`ALU_COUNT]; // pkts to ALU 
    issue_packet_t mul_req  [`MUL_COUNT];
    issue_packet_t load_req [`LOAD_COUNT];
    issue_packet_t br_req   [`BR_COUNT];

    assign rd_en = '1;
    always_ff @(posedge clock) begin //###
        raddr[0] <= alu_req[0].src1_val; 
        raddr[1] <= alu_req[0].src2_val; 
        raddr[2] <= mul_req[0].src1_val; 
        raddr[3] <= mul_req[0].src2_val; 
        raddr[4] <= load_req[0].src1_val; 
        raddr[5] <= load_req[0].src2_val; 
        raddr[6] <= br_req[0].src1_val; 
        raddr[7] <= br_req[0].src2_val;
    end

// S/EX
    issue_packet_t alu_req_reg  [`ALU_COUNT]; // pkts to ALU 
    issue_packet_t mul_req_reg  [`MUL_COUNT];
    issue_packet_t load_req_reg [`LOAD_COUNT];
    issue_packet_t br_req_reg   [`BR_COUNT];

    issue_packet_t alu_req_reg_org  [`ALU_COUNT]; // pkts to ALU 
    issue_packet_t mul_req_reg_org  [`MUL_COUNT];
    issue_packet_t load_req_reg_org [`LOAD_COUNT];
    issue_packet_t br_req_reg_org   [`BR_COUNT];


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
    logic [`XLEN-1:0]          fu_value_wb; //### sychenn 11/7 ###///
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
    COMMIT_PACKET [`N-1:0]  wb_packet;

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
        // TODO: now only has icache
        proc2mem_command = Imem_command;
        proc2mem_addr    = Imem_addr;
        // if (Dmem_command != MEM_NONE) begin  // read or write DATA from memory
        //     proc2mem_command = Dmem_command_filtered;
        //     proc2mem_size    = Dmem_size;
        //     proc2mem_addr    = Dmem_addr;
        // end else begin                      // read an INSTRUCTION from memory
        //     proc2mem_command = Imem_command;
        //     proc2mem_addr    = Imem_addr;
        //     proc2mem_size    = DOUBLE;      // instructions load a full memory line (64 bits)
        // end
        // proc2mem_data = Dmem_store_data;
    end
    assign proc2mem_size = DOUBLE;

    //////////////////////////////////////////////////
    //                                              //
    //                  Valid Bit                   //
    //                                              //
    //////////////////////////////////////////////////

    // This state controls the stall signal that artificially forces IF
    // to stall until the previous instruction has completed.
    // For project 3, start by assigning if_valid to always be 1

    logic if_valid, if_flush,correct_predict;
    logic pred_valid_i, pred_taken_i;
    logic [$clog2(`FETCH_WIDTH)-1:0] pred_lane_i;   // which instruction is branch    
    ADDR pred_target_i; // predicted target PC Addr


    // valid bit will cycle through the pipeline and come back from the wb stage
    // assign if_valid = ((!stall) && (if_packet[0].inst != 32'h10500073)) ? 1'b1 : 1'b0;//###
    always_ff @(negedge clock) begin
        $display("inst : %h", if_packet[0].inst);
    end
    // assign if_valid = 1'b1;
    assign if_valid = !stall;
    //###
    logic [16:0] cycle;
    always @(posedge clock) begin
        if(reset)
            cycle <= 0;
        else
            cycle <= cycle + 1;
    end
    // assign if_valid = (cycle < 45) ? 1'b1 : 1'b0; //###
    // assign if_valid = 1'b1;
    assign correct_predict = (wb_valid[3] & !wb_mispred[3]); //###TODO: CORRECT PREDICT 
    assign if_flush = (wb_valid[3] & wb_mispred[3]); //### open flush
    // assign take_branch = wb_valid[3] & wb_mispred[3];
    assign take_branch = 1'b0;
    // assign if_flush = 1'b0; //### close flush
    // always @(posedge clock) begin
    //     $display("CPU. take_br, wb_valid, wb_mispred=%b %b %b", take_branch, wb_valid, wb_mispred);
    // end
    assign pred_taken_i = 1'b0; //###
    assign pred_valid_i = 1'b0; //###

    int cycle_count;
    always_ff @(posedge clock) begin
        if (reset) begin
            cycle_count <= 0;
        end else begin
            if (if_flush) begin
                $display("if_flush=%b | wb_valid=%b | wb_mispred=%b | wb_rob_idx=%d", if_flush, wb_valid, wb_mispred, wb_rob_idx[3]);
            end else begin
            cycle_count <= cycle_count + 1;
            end
        end
    end
    // assign if_valid = (cycle < 45) ? 1'b1 : 1'b0; //###
    // assign if_valid = 1'b1;
    // assign if_flush = (wb_valid[3] & wb_mispred[3]); //###
    // assign take_branch = wb_valid[3] & wb_mispred[3];
    // assign take_branch = 1'b0;
    // assign if_flush = 1'b0;
    // always @(posedge clock) begin
    //     $display("CPU. take_br, wb_valid, wb_mispred=%b %b %b", take_branch, wb_valid, wb_mispred);
    // end
    // assign pred_taken_i = 1'b0; //###
    // assign pred_valid_i = 1'b0; //###

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

        // From fetch stage (the insturction address)
        .proc2Icache_addr(proc2Icache_addr),

        // Outputs
        // To memory
        .proc2Imem_command(Imem_command), // this let memory know we want to load or store (also act as valid signal)
        .proc2Imem_addr(Imem_addr),

        // To fetch stage
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
        .take_branch(take_branch),     

        .pred_valid_i(pred_valid_i),     
        .pred_lane_i(pred_lane_i),      
        .pred_taken_i(pred_taken_i),     
        .pred_target_i(pred_target_i),    

        // =========================================================
        // Fetch <-> ICache / Mem
        // =========================================================
        // Inputs from icache
        .Icache_valid(Icache_valid_out), // valid signal from I-cache
        .Icache_data (Icache_data_out), // data from I-cache (instruction)

        // Outputs
        // These now go to the I-Cache, NOT main memory
        // .Imem_command (Imem_command),  //### initially fetch -> mem so has this line (now control by icache)
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
    // assign if_id_enable = 1'b1;//###

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
                if_id_reg[i].inst <= if_packet[i].inst;
                if_id_reg[i].NPC <= if_packet[i].NPC;
                if_id_reg[i].PC <= if_packet[i].PC;
                if(if_packet[i].inst == 0 || !(if_packet[i].valid)) begin
                    if_id_reg[i].valid <= `FALSE;
                end else begin
                    if_id_reg[i].valid <= `TRUE;
                end
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
    assign disp_rob_space = (free_rob_slots > `DISPATCH_WIDTH) ? `DISPATCH_WIDTH : free_rob_slots[`DISPATCH_WIDTH-1:0]; 
    assign disp_free_space = (free_count > `DISPATCH_WIDTH) ? `DISPATCH_WIDTH : free_count[`DISPATCH_WIDTH-1:0];
    // assign disp_free_space = 1'b1; //###
    dispatch_stage dispatch_stage_0(
        .clock (clock),
        .reset (reset),

        .if_packet_i(if_id_reg),
        //free list inputs
        .free_regs_i(disp_free_space),
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
        .is_branch_o(is_branch),

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
        .free_rob_slots_i(disp_rob_space),
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
        .disp_packet_i(disp_packet),

        // Writeback
        .wb_valid_i(wb_valid),
        .wb_rob_idx_i(wb_rob_idx),
        .wb_exception_i(wb_exception),
        .wb_mispred_i(wb_mispred), //###
        .fu_value_wb_i(fu_value_wb), ///### sychenn 11/7 ###///

        // Commit
        .commit_valid_o(commit_valid),
        .commit_rd_wen_o(commit_rd_wen),
        .commit_rd_arch_o(commit_rd_arch),
        .commit_new_prf_o(commit_new_prf),
        .commit_old_prf_o(commit_old_prf),

        // Branch flush
        .flush_o(flush_rob),
        .flush_upto_rob_idx_o(flush_upto_rob_idx),

        // Mispredict flush (sychenn 11/6)
        .mispredict_i(if_flush),
        .mispredict_rob_idx_i(wb_rob_idx[3]),
         //### TODO: for debug only (sychenn 11/6) ###//
        .flush_i(flush_rob_debug),
        .flush_free_regs_valid(flush_free_regs_valid),
        .flush_free_regs(flush_free_regs),
        .wb_packet_o(wb_packet)
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
        //###

        .wb_valid_i(cdb_valid_mp),//
        .wb_phys_i(cdb_phy_tag_mp),//

        .is_branch_i(is_branch),
        .flush_i('0),
        .snapshot_restore_valid_i(snapshot_restore_i),
        .snapshot_data_i(snapshot_data_i),

        .snapshot_data_o(snapshot_data_o),
        .checkpoint_valid_o(checkpoint_valid)
    );

    //### 11/10 sychenn ###// (for map table restore)
    always_ff @(posedge clock or posedge reset) begin : checkpoint
        if (reset) begin
            // snapshot_reg       <= '{default:'{phys:'0, valid:'0}};
            // snapshot_data_i    <= '{default:'{phys:'0, valid:'0}};
            for(int i =0 ; i < `ARCH_REGS ; i++)begin
                snapshot_reg[i].phys <= '0;
                snapshot_reg[i].valid <= '0;
                // $display("snapshot_reg[%0d] = %d (%d)",i,snapshot_reg[i].phys,snapshot_reg[i].valid);
            end
            // snapshot_reg       <= '0;
            // snapshot_data_i    <= '0;
            snapshot_restore_i <= 1'b0;
            has_snapshot       <= 1'b0;
        end else begin
            // $display("snapshot_reg:");
            // for(int i =0 ; i < `ARCH_REGS ; i++)begin
            //     $display("snapshot_reg[%0d] = %d (%d)",i,snapshot_reg[i].phys,snapshot_reg[i].valid);
            // end
            if (if_flush && has_snapshot) begin
                for(int i =0 ; i <`ARCH_REGS ; i++)begin
                    snapshot_data_i[i].phys <= snapshot_reg[i].phys;
                    snapshot_data_i[i].valid <= snapshot_reg[i].valid;
                end
                snapshot_restore_i <= 1'b1;
                has_snapshot       <= 1'b0; // consume snapshot
            end else if (checkpoint_valid) begin
                for(int i =0 ; i < `ARCH_REGS ; i++)begin
                    snapshot_reg[i].phys <= snapshot_data_o[i].phys;
                    snapshot_reg[i].valid <= snapshot_data_o[i].valid;
                end
                has_snapshot <= 1'b1;
            end else begin
                snapshot_restore_i <= 1'b0;
            end
        end
    end
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
        .free_count_o(free_count),

        //### TODO: for debug only (sychenn 11/6) ###//
        .flush_i(flush_rob_debug),
        .flush_free_regs_valid(flush_free_regs_valid),
        .flush_free_regs(flush_free_regs)

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
        // .flush('0),
        // .flush(flush),
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
        .fu_type_o(fu_types),

        //flush (br)
        .br_mispredict_i(if_flush),
        .branch_success_predict(correct_predict)
    );

    //////////////////////////////////////////////////
    //                                              //
    //            ID/S Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

    assign id_s_enable = !stall;
    // assign id_s_enable = 1'b1;

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
    // logic s_ex_stall;
    // always_ff @(posedge clock) begin
    //     s_ex_stall <= stall;
    // end
    // assign s_ex_enable = !s_ex_stall;
    assign s_ex_enable = 1'b1;

    always_ff @(posedge clock) begin
        if (reset) begin
            // Clear all FU request registers
            alu_req_reg_org[0]   <= '0;
            mul_req_reg_org[0]   <= '0;
            load_req_reg_org[0]  <= '0;
            br_req_reg_org[0]    <= '0;

            alu_req_reg[0].valid       <= '0;
            alu_req_reg[0].rob_idx     <= '0;
            alu_req_reg[0].imm         <= '0;
            alu_req_reg[0].fu_type     <= '0;
            alu_req_reg[0].opcode      <= '0;
            alu_req_reg[0].dest_tag    <= '0;
            alu_req_reg[0].src2_valid  <= '0;
            alu_req_reg[0].disp_packet <= '0;

            mul_req_reg[0].valid       <= '0;
            mul_req_reg[0].rob_idx     <= '0;
            mul_req_reg[0].imm         <= '0;
            mul_req_reg[0].fu_type     <= '0;
            mul_req_reg[0].opcode      <= '0;
            mul_req_reg[0].dest_tag    <= '0;
            mul_req_reg[0].src2_valid  <= '0;
            mul_req_reg[0].disp_packet <= '0;

            load_req_reg[0].valid       <= '0;
            load_req_reg[0].rob_idx     <= '0;
            load_req_reg[0].imm         <= '0;
            load_req_reg[0].fu_type     <= '0;
            load_req_reg[0].opcode      <= '0;
            load_req_reg[0].dest_tag    <= '0;
            load_req_reg[0].src2_valid  <= '0;
            load_req_reg[0].disp_packet <= '0;

            br_req_reg[0].valid       <= '0; 
            br_req_reg[0].rob_idx     <= '0;
            br_req_reg[0].imm         <= '0;
            br_req_reg[0].fu_type     <= '0;
            br_req_reg[0].opcode      <= '0;
            br_req_reg[0].dest_tag    <= '0;
            br_req_reg[0].src2_valid  <= '0;
            br_req_reg[0].disp_packet <= '0;


            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			    s_ex_reg[i] <= '0;
		    end
        end else if (s_ex_enable) begin
            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
			    s_ex_reg[i] <= issue_packet[i];
		    end

            alu_req_reg_org[0] <= alu_req[0];
            mul_req_reg_org[0] <= mul_req[0];
            load_req_reg_org[0] <= load_req[0];
            br_req_reg_org[0]  <= br_req[0];

            alu_req_reg[0].valid <= alu_req[0].valid;
            alu_req_reg[0].rob_idx <= alu_req[0].rob_idx;
            alu_req_reg[0].imm <= alu_req[0].imm;
            alu_req_reg[0].fu_type <= alu_req[0].fu_type;
            alu_req_reg[0].opcode <= alu_req[0].opcode;
            alu_req_reg[0].dest_tag <= alu_req[0].dest_tag;
            alu_req_reg[0].src2_valid <= alu_req[0].src2_valid;
            alu_req_reg[0].disp_packet <= alu_req[0].disp_packet;
            
            mul_req_reg[0].valid <= mul_req[0].valid;
            mul_req_reg[0].rob_idx <= mul_req[0].rob_idx;
            mul_req_reg[0].imm <= mul_req[0].imm;
            mul_req_reg[0].fu_type <= mul_req[0].fu_type;
            mul_req_reg[0].opcode <= mul_req[0].opcode;
            mul_req_reg[0].dest_tag <= mul_req[0].dest_tag;
            mul_req_reg[0].src2_valid <= mul_req[0].src2_valid;
            mul_req_reg[0].disp_packet <= mul_req[0].disp_packet;

            load_req_reg[0].valid <= load_req[0].valid;
            load_req_reg[0].rob_idx <= load_req[0].rob_idx;
            load_req_reg[0].imm <= load_req[0].imm;
            load_req_reg[0].fu_type <= load_req[0].fu_type;
            load_req_reg[0].opcode <= load_req[0].opcode;
            load_req_reg[0].dest_tag <= load_req[0].dest_tag;
            load_req_reg[0].src2_valid <= load_req[0].src2_valid;
            load_req_reg[0].disp_packet <= load_req[0].disp_packet;

            br_req_reg[0].valid <= br_req[0].valid; 
            br_req_reg[0].rob_idx <= br_req[0].rob_idx;
            br_req_reg[0].imm <= br_req[0].imm;
            br_req_reg[0].fu_type <= br_req[0].fu_type;
            br_req_reg[0].opcode <= br_req[0].opcode;
            br_req_reg[0].dest_tag <= br_req[0].dest_tag;
            br_req_reg[0].src2_valid <= br_req[0].src2_valid;
            br_req_reg[0].disp_packet <= br_req[0].disp_packet;
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
    // always_ff @(negedge clock) begin
    //     $display("rob=%d | dast_tag=%d | src1_val =%h | src2_val %h", alu_req_reg[0].rob_idx, alu_req_reg[0].dest_tag, alu_req_reg[0].src1_val, alu_req_reg[0].src2_val);
    //     $display("MUL: rob=%d | dast_tag=%d | src1_val =%h | src2_val %h | res %h", mul_req_reg[0].rob_idx, mul_req_reg[0].dest_tag, mul_req_reg[0].src1_val, mul_req_reg[0].src2_val, fu_resp_bus[1].value);
    // end
    
    assign alu_req_reg[0].src1_val = rdata[0];
    assign alu_req_reg[0].src2_val = alu_req_reg_org[0].src2_valid ? rdata[1] : alu_req_reg_org[0].src2_val; 
    assign mul_req_reg[0].src1_val = rdata[2];
    assign mul_req_reg[0].src2_val = mul_req_reg_org[0].src2_valid ? rdata[3] : mul_req_reg_org[0].src2_val;
    assign load_req_reg[0].src1_val = rdata[4];
    assign load_req_reg[0].src2_val = load_req_reg_org[0].src2_valid ? rdata[5] : load_req_reg_org[0].src2_val;
    assign br_req_reg[0].src1_val = rdata[6];
    assign br_req_reg[0].src2_val = br_req_reg_org[0].src2_valid ? rdata[7] : br_req_reg_org[0].src2_val;
    
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

    // always_ff @(negedge clock) begin
    //     $display("fu br rob out valid, idx: %b, %d", fu_valid[3], fu_rob_idx[3]);
    // end

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
            fu_valid_reg <= '0;
            fu_value_reg <= '0;
            fu_dest_prf_reg <= '0;
            fu_rob_idx_reg <= '0;
            fu_exception_reg <= '0;
            fu_mispred_reg <= '0;
        end else begin
            fu_valid_reg <= fu_valid;
            fu_value_reg <= fu_value;
            fu_dest_prf_reg <= fu_dest_prf;
            fu_rob_idx_reg <= fu_rob_idx;
            fu_exception_reg <= fu_exception;
            fu_mispred_reg <= fu_mispred;


            for(int i=0;i<`DISPATCH_WIDTH;i++) begin
                ex_c_inst_dbg[i] <= s_ex_inst_dbg[i]; // debug output, just forwarded from ID
                ex_c_reg[i] <= ex_packet[i];
            end
        end
    end

    // always_ff @(negedge clock) begin
    //     $display("fu_valid : %b", fu_valid_reg);
    // end

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
        .wb_value_o(fu_value_wb), ///### sychenn 11/7 ###///

        // cdb
        .cdb_o(cdb_packets)
    );
    // always_ff @(negedge clock) begin
    //     $display("Complete input: CDB_alu_value=%d | CDB_mul_value=%d | CDB_br_value=%d", fu_value_reg[0], fu_value_reg[1], fu_value_reg[3]);
    //     $display("Complete: CDB_alu_value=%d | CDB_mul_value=%d | CDB_br_value=%d | wb_valid=%b | wb_mis_pred=%b | wb_rob_idx=%d ", cdb_packets[0].value, cdb_packets[1].value, cdb_packets[3].value, wb_valid, wb_mispred[3], wb_rob_idx[3]);
    // end
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
        // .flush_i(flush_rob),
        .flush_i('0),

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
    assign committed_insts = wb_packet;
always_ff @(posedge clock) begin
    if (!reset) begin
        integer i;
        for (i = 0; i < `N; i++) begin
            $display("Commit[%0d]: valid=%b halt=%b illegal=%b reg=%0d data=%h NPC=%h",
                     i,
                     committed_insts[i].valid,
                     committed_insts[i].halt,
                     committed_insts[i].illegal,
                     committed_insts[i].reg_idx,
                     committed_insts[i].data,
                     committed_insts[i].NPC);
        end
        $display("-------------------\n");
    end
end

endmodule // pipeline
