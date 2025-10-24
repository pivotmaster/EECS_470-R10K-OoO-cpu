`ifndef __DEFS_SVH__
`define __DEFS_SVH__

typedef struct packed {
    logic                          valid;     // = busy
    logic [$clog2(ROB_DEPTH)-1:0]  rob_idx;
    logic [$clog2(ARCH_REGS)-1:0]  dest_arch_reg; // for cdb update map table
    logic [$clog2(PHYS_REGS)-1:0]  dest_tag;  // write reg
    logic [$clog2(PHYS_REGS)-1:0]  src1_tag;  // source reg 1      
    logic [$clog2(PHYS_REGS)-1:0]  src2_tag;  // source reg 2
    logic                          src1_ready; // is value of source reg 1 ready?
    logic                          src2_ready; // is value of source reg 2 ready?
    DISP_PACKET                   disp_packet; //decoder_o 
} rs_entry_t;

typedef struct packed {
    logic                         valid;
    logic                         done;
    logic                         exception;
    logic [$clog2(ARCH_REGS)-1:0] dest_arch;
    logic [$clog2(PHYS_REGS)-1:0] dest_prf;
    logic [$clog2(PHYS_REGS)-1:0] old_prf;
    logic [$clog2(ROB_DEPTH)-1:0] rob_idx;
    logic                         is_branch;
    logic                         mispredicted;
} rob_entry_t;

typedef struct packed {
    logic                         valid;      // broadcast valid
    logic [$clog2(ARCH_REGS)-1:0] dest_arch;  // Arch reg
    logic [$clog2(PHYS_REGS)-1:0] phys_tag;   // PRF tag
    logic [XLEN-1:0]              value;      // result value
} cdb_entry_t;

typedef struct packed {
    INST  inst;
    ADDR  PC;
    ADDR  NPC; // PC + 4
    logic valid;
} IF_ID_PACKET;

typedef struct packed {
    INST inst;
    ADDR PC;
    ADDR NPC; // PC + 4

    //DATA rs1_value; // reg A value
    //DATA rs2_value; // reg B value

    ALU_OPA_SELECT opa_select; // ALU opa mux select (ALU_OPA_xxx *)
    ALU_OPB_SELECT opb_select; // ALU opb mux select (ALU_OPB_xxx *)

    REG_IDX  dest_reg_idx;  // destination (writeback) register index
    ALU_FUNC alu_func;      // ALU function select (ALU_xxx *)
    logic    mult;          // Is inst a multiply instruction?
    logic    rd_mem;        // Does inst read memory?
    logic    wr_mem;        // Does inst write memory?
    logic    cond_branch;   // Is inst a conditional branch?
    logic    uncond_branch; // Is inst an unconditional branch?
    logic    halt;          // Is this a halt?
    logic    illegal;       // Is this instruction illegal?
    logic    csr_op;        // Is this a CSR operation? (we only used this as a cheap way to get return code)

    logic    valid;
} DISP_PACKET;