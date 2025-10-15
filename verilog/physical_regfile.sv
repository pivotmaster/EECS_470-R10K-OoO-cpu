module #(
    parameter int unsigned PHYS_REGS = 128,
    parameter int unsigned XLEN      = 64,
    parameter int unsigned READ_PORTS = 4,
    parameter int unsigned WRITE_PORTS = 4,
    parameter bit          BYPASS_EN    = 1
)(
    input logic clk,
    input logic reset,
    //---------------- read ports (from issue stage / rename) ----------------
    input  logic [READ_PORTS-1:0]rd_en, 
    input  logic [READ_PORTS-1:0][$clog2(PHYS_REGS)-1:0] raddr,
    output logic [READ_PORTS-1:0][XLEN-1:0]          rdata_o,
    //---------------- write ports ----------------
    input  logic [WRITE_PORTS-1:0] wr_en, 
    input  logic [WRITE_PORTS-1:0][$clog2(PHYS_REGS)-1:0] waddr,
    input  logic [WRITE_PORTS-1:0][XLEN-1:0]          wdata
);
endmodule