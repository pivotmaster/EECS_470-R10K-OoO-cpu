`include "def.svh"
module complete_stage #(
    parameter int unsigned XLEN       = 32,
    parameter int unsigned PHYS_REGS  = 128,
    parameter int unsigned ROB_DEPTH  = 64,
    parameter int unsigned WB_WIDTH   = 4,
    parameter int unsigned CDB_WIDTH  = 4
)(
    input  logic clock,
    input  logic reset,

    // LSQ (only load instruction)
    input logic       wb_valid,
    input ROB_IDX     wb_rob_idx,
    input logic [31:0]   wb_data, 
    input logic [$clog2(PHYS_REGS)-1:0] wb_disp_rd_new_prf_i,

    // FU
    input  logic [WB_WIDTH-1:0]                    fu_valid_i,
    input  logic [WB_WIDTH-1:0][XLEN-1:0]          fu_value_i,
    input  logic [WB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] fu_dest_prf_i,
    input  logic [WB_WIDTH-1:0][$clog2(ROB_DEPTH)-1:0] fu_rob_idx_i,
    input  logic [WB_WIDTH-1:0]                    fu_exception_i,
    input  logic [WB_WIDTH-1:0]                    fu_mispred_i,

    // PR
    output logic [WB_WIDTH-1:0]                    prf_wr_en_o,
    output logic [WB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] prf_waddr_o,
    output logic [WB_WIDTH-1:0][XLEN-1:0]          prf_wdata_o,

    // rob
    output logic [WB_WIDTH-1:0]                    wb_valid_o,
    output logic [WB_WIDTH-1:0][$clog2(ROB_DEPTH)-1:0] wb_rob_idx_o,
    output logic [WB_WIDTH-1:0]                    wb_exception_o,
    output logic [WB_WIDTH-1:0]                    wb_mispred_o,
    output logic [WB_WIDTH-1:0][XLEN-1:0]          wb_value_o,

    // cdb
    output cdb_entry_t [CDB_WIDTH-1:0]             cdb_o
);

    // int idx;
    always_comb begin
        // idx = 0;
        prf_wr_en_o   = '0;
        prf_waddr_o   = '0;
        prf_wdata_o   = '0;
        wb_valid_o    = '0;
        wb_rob_idx_o  = '0;
        wb_exception_o = '0;
        wb_mispred_o   = '0;
        wb_value_o    = '0;
        cdb_o          = '0;

        for (int i = 0; i < WB_WIDTH; i++) begin
            if (fu_valid_i[i]) begin
                prf_wr_en_o[i]   = 1'b1;
                prf_waddr_o[i]   = fu_dest_prf_i[i];
                prf_wdata_o[i]   = fu_value_i[i];

                wb_valid_o[i]     = 1'b1;
                wb_rob_idx_o[i]   = fu_rob_idx_i[i];
                wb_exception_o[i] = fu_exception_i[i];
                wb_mispred_o[i]   = fu_mispred_i[i];
                wb_value_o[i]   = fu_value_i[i]; // 11/21 sychenn

                cdb_o[i].valid     = 1'b1;
                cdb_o[i].dest_arch = '0; //todo: why is zero?
                cdb_o[i].phys_tag  = fu_dest_prf_i[i];
                cdb_o[i].value     = fu_value_i[i];          
            end else  if (wb_valid) begin 
                // todo: lsq wb is valid
                $display("complete stage: wb_valid=%b | wb_rob_idx=%d | wb_data=%h | wb_disp_rd_new_prf_i=%d ",wb_valid, wb_rob_idx, wb_data, wb_disp_rd_new_prf_i);
                // from lsq
                prf_wr_en_o[i]   = wb_valid;
                prf_waddr_o[i]   = wb_disp_rd_new_prf_i;
                prf_wdata_o[i]   = wb_data;

                wb_valid_o[i]     = wb_valid;
                wb_rob_idx_o[i]   = wb_rob_idx;
                wb_exception_o[i] = '0;
                wb_mispred_o[i]   = '0;
                wb_value_o[i]   = wb_data;

                cdb_o[i].valid     = wb_valid;
                cdb_o[i].dest_arch = '0;
                cdb_o[i].phys_tag  = wb_disp_rd_new_prf_i;
                cdb_o[i].value     =wb_data; 
            end
            // $display("complete stage i, out, in = %0d, %0d, %0d", i, cdb_o[i].value, fu_value_i[i]);
        end
    end

endmodule

