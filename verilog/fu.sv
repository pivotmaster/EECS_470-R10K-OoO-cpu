`include "def.svh"

// ---------------- ALU FU ----------------
module alu_fu #(
  parameter int XLEN = 64,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
  input  issue_packet_t req_i,
  output fu_resp_t      resp_o,
  output logic          ready_o
);
  logic [XLEN-1:0] result;

  always_comb begin
    unique case (req_i.opcode)
      4'd0: result = req_i.src1_val + req_i.src2_val;
      4'd1: result = req_i.src1_val - req_i.src2_val;
      4'd2: result = req_i.src1_val & req_i.src2_val;
      4'd3: result = req_i.src1_val | req_i.src2_val;
      4'd4: result = req_i.src1_val ^ req_i.src2_val;
      4'd5: result = req_i.src1_val << req_i.src2_val[5:0];
      4'd6: result = req_i.src1_val >> req_i.src2_val[5:0];
      4'd7: result = $signed(req_i.src1_val) >>> req_i.src2_val[5:0];
      4'd8: result = ($signed(req_i.src1_val) <  $signed(req_i.src2_val));
      4'd9: result = (req_i.src1_val < req_i.src2_val);
      default: result = '0;
    endcase
  end

  assign ready_o = 1'b1;
  always_comb begin
    resp_o.valid     = req_i.valid;
    resp_o.value     = result;
    resp_o.dest_prf  = req_i.dest_tag;
    resp_o.rob_idx   = req_i.rob_idx;
    resp_o.exception = 1'b0;
    resp_o.mispred   = 1'b0;
  end
endmodule


// ---------------- MUL FU ----------------
module mul_fu #(
  parameter int XLEN = 64,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
  input  issue_packet_t req_i,
  output fu_resp_t      resp_o,
  output logic          ready_o
);
  logic [2*XLEN-1:0] product;
  assign product = $signed(req_i.src1_val) * $signed(req_i.src2_val);

  assign ready_o = 1'b1;
  always_comb begin
    resp_o.valid     = req_i.valid;
    resp_o.value     = product[XLEN-1:0];
    resp_o.dest_prf  = req_i.dest_tag;
    resp_o.rob_idx   = req_i.rob_idx;
    resp_o.exception = 1'b0;
    resp_o.mispred   = 1'b0;
  end
endmodule


// ---------------- LOAD FU ----------------
module load_fu #(
  parameter int XLEN = 64,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
  input  issue_packet_t req_i,
  output fu_resp_t      resp_o,
  output logic          ready_o
);
  logic [XLEN-1:0] addr;
  assign addr = req_i.src1_val + {{(XLEN-12){req_i.imm[11]}}, req_i.imm[11:0]};

  assign ready_o = 1'b1;
  always_comb begin
    resp_o.valid     = req_i.valid;
    resp_o.value     = addr;
    resp_o.dest_prf  = req_i.dest_tag;
    resp_o.rob_idx   = req_i.rob_idx;
    resp_o.exception = 1'b0;
    resp_o.mispred   = 1'b0;
  end
endmodule


// ---------------- BRANCH FU ----------------
module branch_fu #(
  parameter int XLEN = 64,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
  input  issue_packet_t req_i,
  output fu_resp_t      resp_o,
  output logic          ready_o
);
  logic take;
  always_comb begin
    unique case (req_i.opcode[2:0])
      3'b000: take = ($signed(req_i.src1_val) == $signed(req_i.src2_val));
      3'b001: take = ($signed(req_i.src1_val) != $signed(req_i.src2_val));
      3'b100: take = ($signed(req_i.src1_val) <  $signed(req_i.src2_val));
      3'b101: take = ($signed(req_i.src1_val) >= $signed(req_i.src2_val));
      3'b110: take = (req_i.src1_val <  req_i.src2_val);
      3'b111: take = (req_i.src1_val >= req_i.src2_val);
      default: take = 1'b0;
    endcase
  end

  assign ready_o = 1'b1;
  always_comb begin
    resp_o.valid     = req_i.valid;
    resp_o.value     = {{(XLEN-1){1'b0}}, take};
    resp_o.dest_prf  = req_i.dest_tag;
    resp_o.rob_idx   = req_i.rob_idx;
    resp_o.exception = 1'b0;
    resp_o.mispred   = 1'b0;
  end
endmodule


module fu #(
  parameter int XLEN        = 64,
  parameter int PHYS_REGS   = 128,
  parameter int ROB_DEPTH   = 64,
  parameter int ALU_COUNT   = 1,
  parameter int MUL_COUNT   = 1,
  parameter int LOAD_COUNT  = 1,
  parameter int BR_COUNT    = 1
)(
    // Issue → FU
    input  issue_packet_t alu_req  [ALU_COUNT],
    input  issue_packet_t mul_req  [MUL_COUNT],
    input  issue_packet_t load_req [LOAD_COUNT],
    input  issue_packet_t br_req   [BR_COUNT],

    // FU → Issue
    output logic   alu_ready_o  [ALU_COUNT],
    output logic   mul_ready_o  [MUL_COUNT],
    output logic   load_ready_o [LOAD_COUNT],
    output logic   br_ready_o   [BR_COUNT],

    // FU responses (for debug / tracing)
    output fu_resp_t fu_resp_bus [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT],

    // FU → Complete Stage (flattened)
    output logic [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0]                    fu_valid_o,
    output logic [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0][XLEN-1:0]          fu_value_o,
    output logic [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0][$clog2(PHYS_REGS)-1:0] fu_dest_prf_o,
    output logic [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0][$clog2(ROB_DEPTH)-1:0] fu_rob_idx_o,
    output logic [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0]                    fu_exception_o,
    output logic [ALU_COUNT+MUL_COUNT+LOAD_COUNT+BR_COUNT-1:0]                    fu_mispred_o
);

  localparam int TOTAL_FU = ALU_COUNT + MUL_COUNT + LOAD_COUNT + BR_COUNT;

  genvar i;
  generate
    // ---------------- ALU ----------------
    for (i = 0; i < ALU_COUNT; i++) begin : GEN_ALU
      alu_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH)) u_alu (
        .req_i  (alu_req[i]),
        .resp_o (fu_resp_bus[i]),
        .ready_o(alu_ready_o[i])
      );
    end

    // ---------------- MUL ----------------
    for (i = 0; i < MUL_COUNT; i++) begin : GEN_MUL
      localparam int IDX = ALU_COUNT + i;
      mul_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH)) u_mul (
        .req_i  (mul_req[i]),
        .resp_o (fu_resp_bus[IDX]),
        .ready_o(mul_ready_o[i])
      );
    end

    // ---------------- LOAD ----------------
    for (i = 0; i < LOAD_COUNT; i++) begin : GEN_LOAD
      localparam int IDX = ALU_COUNT + MUL_COUNT + i;
      load_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH)) u_load (
        .req_i  (load_req[i]),
        .resp_o (fu_resp_bus[IDX]),
        .ready_o(load_ready_o[i])
      );
    end

    // ---------------- BRANCH ----------------
    for (i = 0; i < BR_COUNT; i++) begin : GEN_BR
      localparam int IDX = ALU_COUNT + MUL_COUNT + LOAD_COUNT + i;
      branch_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH)) u_br (
        .req_i  (br_req[i]),
        .resp_o (fu_resp_bus[IDX]),
        .ready_o(br_ready_o[i])
      );
    end
  endgenerate

  // ==========================================================
  // ===             Flatten response for WB bus             ===
  // ==========================================================
  integer k;
  always_comb begin
    for (k = 0; k < TOTAL_FU; k++) begin
      fu_valid_o    [k] = fu_resp_bus[k].valid;
      fu_value_o    [k] = fu_resp_bus[k].value;
      fu_dest_prf_o [k] = fu_resp_bus[k].dest_prf;
      fu_rob_idx_o  [k] = fu_resp_bus[k].rob_idx;
      fu_exception_o[k] = fu_resp_bus[k].exception;
      fu_mispred_o  [k] = fu_resp_bus[k].mispred;
    end
  end

endmodule