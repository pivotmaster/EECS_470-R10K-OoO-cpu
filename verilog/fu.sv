`include "def.svh"

// ---------------- ALU FU ----------------
module alu_fu #(
  parameter int XLEN = 32,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
  input  issue_packet_t req_i,
  output fu_resp_t      resp_o,
  output logic          ready_o
);
  logic [XLEN-1:0] result;
    always_comb begin
        case (req_i.opcode)
            ALU_ADD:  result = req_i.src1_val + req_i.src2_val;
            ALU_SUB:  result = req_i.src1_val - req_i.src2_val;
            ALU_AND:  result = req_i.src1_val & req_i.src2_val;
            ALU_SLT:  result = signed'(req_i.src1_val) < signed'(req_i.src2_val);
            ALU_SLTU: result = req_i.src1_val < req_i.src2_val;
            ALU_OR:   result = req_i.src1_val | req_i.src2_val;
            ALU_XOR:  result = req_i.src1_val ^ req_i.src2_val;
            ALU_SRL:  result = req_i.src1_val >> req_i.src2_val[4:0];
            ALU_SLL:  result = req_i.src1_val << req_i.src2_val[4:0];
            ALU_SRA:  result = signed'(req_i.src1_val) >>> req_i.src2_val[4:0]; // arithmetic from logical shift
            // here to prevent latches:
            default:  result = 32'hfacebeec;
        endcase
    end

/*
  always_comb begin
    unique case (req_i.opcode)
      4'd0: result = req_i.src1_val + req_i.src2_val;
      4'd1: result = req_i.src1_val - req_i.src2_val;
      4'd2: result = req_i.src1_val & req_i.src2_val;
      4'd3: result = req_i.src1_val | req_i.src2_val;
      4'd4: result = req_i.src1_val ^ req_i.src2_val;
      4'd5: result = req_i.src1_val << req_i.src2_val[5:0];
      4'd6: result = req_i.src1_val >> req_i.src2_val[5:0];
      4'd7: result = $signed(req_i.src1_val) <<< req_i.src2_val[5:0];
      4'd8: result = ($signed(req_i.src1_val) <  $signed(req_i.src2_val));
      4'd9: result = (req_i.src1_val < req_i.src2_val);
      default: result = '0;
    endcase
  end*/

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
/* initial one
module mul_fu #(
  parameter int XLEN = 32,
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
*/

module mul_fu #(
  parameter int XLEN = 32,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
    input  issue_packet_t req_i,

    output fu_resp_t      resp_o,
    output logic  ready_o
);
 assign ready_o = 1;

    logic [63:0] mcand, mplier, product;
    logic [31:0] rs1, rs2;
    logic [XLEN-1:0] result;

    assign rs1 = req_i.src1_val;
    assign rs2 = req_i.src2_val;

    assign product = mcand * mplier;

    // Sign-extend the multiplier inputs based on the operation
    always_comb begin
        case (req_i.disp_packet.inst.r.funct3)
            M_MUL, M_MULH, M_MULHSU: mcand = {{(32){rs1[31]}}, rs1};
            default:                 mcand = {32'b0, rs1};
        endcase
        case (req_i.disp_packet.inst.r.funct3)
            M_MUL, M_MULH: mplier = {{(32){rs2[31]}}, rs2};
            default:       mplier = {32'b0, rs2};
        endcase
    end

    // Use the high or low bits of the product based on the output func
    assign result = (req_i.disp_packet.inst.r.funct3 == M_MUL) ? product[31:0] : product[63:32];

    always_comb begin
      resp_o.valid     = req_i.valid;
      resp_o.value     = result;
      resp_o.dest_prf  = req_i.dest_tag;
      resp_o.rob_idx   = req_i.rob_idx;
      resp_o.exception = 1'b0;
      resp_o.mispred   = 1'b0;
    end

endmodule  

// ---------------- LOAD FU ----------------
module load_fu #(
  parameter int XLEN = 32,
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
  parameter int XLEN = 32,
  parameter int PHYS_REGS = 128,
  parameter int ROB_DEPTH = 64
)(
  input  issue_packet_t req_i,
  output fu_resp_t      resp_o,
  output logic          ready_o
);

  fu_resp_t resp_local_o;

  alu_fu #(.XLEN(XLEN), .PHYS_REGS(PHYS_REGS), .ROB_DEPTH(ROB_DEPTH)) u_alu_br (
        .req_i  (req_i),
        .resp_o (resp_local_o),
        .ready_o(ready_o)
      );

  logic take;
  
  always_comb begin
          case (req_i.disp_packet.inst.b.funct3)
              3'b000:  take = signed'(req_i.src1_val) == signed'(req_i.src2_val); // BEQ
              3'b001:  take = signed'(req_i.src1_val) != signed'(req_i.src2_val); // BNE
              3'b100:  take = signed'(req_i.src1_val) <  signed'(req_i.src2_val); // BLT
              3'b101:  take = signed'(req_i.src1_val) >= signed'(req_i.src2_val); // BGE
              3'b110:  take = req_i.src1_val < req_i.src2_val;                    // BLTU
              3'b111:  take = req_i.src1_val >= req_i.src2_val;                   // BGEU
              default: take = `FALSE;
          endcase
      end

  // assign ready_o = 1'b1;

  always_comb begin
    resp_o.valid     = req_i.valid;
    resp_o.value     = resp_local_o.value; // alu value
    resp_o.dest_prf  = req_i.dest_tag;
    resp_o.rob_idx   = req_i.rob_idx;
    resp_o.exception = 1'b1; // TODO: is branch
    resp_o.mispred   = take;
  end
endmodule


module fu #(
  parameter int XLEN        = 32,
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
  // always_ff @(negedge clock)

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