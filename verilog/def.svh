`ifndef __DEFS_SVH__
`define __DEFS_SVH__

typedef struct packed {
    logic                          valid;     // = busy
    logic [$clog2(ROB_DEPTH)-1:0]  rob_idx;
    logic [31:0]                   imm;
    logic [8:0]                    fu_type;   // on hot code
    logic [$clog2(OPCODE_N)-1:0]   opcode;
    logic [$clog2(PHYS_REGS)-1:0]  dest_tag;  // write reg
    logic [$clog2(PHYS_REGS)-1:0]  src1_tag;  // source reg 1      
    logic [$clog2(PHYS_REGS)-1:0]  src2_tag;  // source reg 2
    logic                          src1_ready; // is value of source reg 1 ready?
    logic                          src2_ready; // is value of source reg 2 ready?
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
    INST  inst;
    ADDR  PC;
    ADDR  NPC; // PC + 4
    logic valid;
} IF_ID_PACKET;