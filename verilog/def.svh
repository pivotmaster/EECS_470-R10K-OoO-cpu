`ifndef __DEF_SVH__
`define __DEF_SVH__

// =========================================================
// Global architectural configuration parameters
// =========================================================

`ifndef XLEN
  `define XLEN            64      // 64-bit processor width
`endif

`ifndef PHYS_REGS
  `define PHYS_REGS       128     // physical register file size
`endif

`ifndef ARCH_REGS
  `define ARCH_REGS       32      // architectural registers (x0–x31)
`endif

`ifndef ROB_DEPTH
  `define ROB_DEPTH       64      // reorder buffer entries
`endif

`ifndef FU_NUM
  `define FU_NUM          8       // total number of functional unit types
`endif

`ifndef OPCODE_N
  `define OPCODE_N        8       // total number of opcodes
`endif


typedef struct packed {
    logic                           valid;     // = busy
    logic [$clog2(`ROB_DEPTH)-1:0]  rob_idx;
    logic [31:0]                    imm;
    logic [$clog2(`FU_NUM)-1:0]     fu_type;   
    logic [$clog2(`OPCODE_N)-1:0]   opcode;
    logic [$clog2(`PHYS_REGS)-1:0]  dest_tag;  // write reg
    logic [$clog2(`PHYS_REGS)-1:0]  src1_tag;  // source reg 1      
    logic [$clog2(`PHYS_REGS)-1:0]  src2_tag;  // source reg 2
    logic                          src1_ready; // is value of source reg 1 ready?
    logic                          src2_ready; // is value of source reg 2 ready?
} rs_entry_t;

typedef struct packed {
    logic                         valid;
    logic                         done;
    logic                         exception;
    logic [$clog2(`ARCH_REGS)-1:0] dest_arch;
    logic [$clog2(`PHYS_REGS)-1:0] dest_prf;
    logic [$clog2(`PHYS_REGS)-1:0] old_prf;
    logic [$clog2(`ROB_DEPTH)-1:0] rob_idx;
    logic                         is_branch;
    logic                         mispredicted;
} rob_entry_t;

typedef struct packed {
    logic                         valid;      // broadcast valid
    logic [$clog2(`ARCH_REGS)-1:0] dest_arch;  // Arch reg
    logic [$clog2(`PHYS_REGS)-1:0] phys_tag;   // PRF tag
    logic [`XLEN-1:0]              value;      // result value
} cdb_entry_t;

  // FU encoding
  typedef enum logic [2:0] {
      FU_ALU    = 3'd0,
      FU_MUL    = 3'd1,
      FU_LOAD   = 3'd2,
      FU_BRANCH = 3'd3
  } fu_type_e;

typedef struct packed {
    logic                          valid;     // = busy
    logic [$clog2(`ROB_DEPTH)-1:0]  rob_idx;
    logic [31:0]                   imm;
    logic [$clog2(`FU_NUM)-1:0]     fu_type;   
    logic [$clog2(`OPCODE_N)-1:0]   opcode;
    logic [$clog2(`PHYS_REGS)-1:0]  dest_tag;  // write reg
    logic [$clog2(`PHYS_REGS)-1:0]  src1_val;  // source reg 1      
    logic [$clog2(`PHYS_REGS)-1:0]  src2_val;  // source reg 2
} issue_packet_t;

`endif // __DEF_SVH__
