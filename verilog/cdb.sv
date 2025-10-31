/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  CDB.sv                                              //
//                                                                     //
//  Description :  Complate Stage -> CDB -> [RS & Map Table]           //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "def.svh"


module cdb #(
    parameter int unsigned CDB_WIDTH  = 4,
    parameter int unsigned PHYS_REGS  = 128,
    parameter int unsigned ARCH_REGS  = 32,
    parameter int unsigned ROB_DEPTH  = 64,
    parameter int unsigned XLEN       = 32
)(
    input  logic clock,
    input  logic reset,

    // =========================================================
    // Complate Stage -> CDB 
    // =========== ============================================== 
    // input  logic        [CDB_WIDTH-1:0]                         complete_cdb_valid_i,
    input  cdb_entry_t  [CDB_WIDTH-1:0]                         cdb_packets_i,

    // =========================================================
    // CDB -> RS 
    // =========================================================   
    output  logic [CDB_WIDTH-1:0]                               cdb_valid_rs_o, 
    output  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]        cdb_tag_rs_o,

    // =========================================================
    // CDB -> Map Table 
    // =========================================================   
    output  logic [CDB_WIDTH-1:0]                               cdb_valid_mp_o,  // commit_valid_i in 'map_table.sv'
    output  logic [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]        cdb_phy_tag_mp_o,
    output  logic [CDB_WIDTH-1:0][$clog2(ARCH_REGS)-1:0]        cdb_dest_arch_mp_o,

    // =========================================================
    // Optional backpressure signals (from RS / MT)
    // =========================================================
    input  logic                                rs_ready_i,
    input  logic                                map_ready_i

);

/*
always_ff @(posedge clock) begin
    if (!reset) begin
        for (int i = 0; i < CDB_WIDTH; i++) begin
            if (cdb_packets_i[i].valid) begin
                $display("[CDB %0t] lane=%0d | arch=%0d | phys=%0d | value=0x%0h | cdb out valid, tag=%0d, %0d",
                         $time,
                         i,
                         cdb_packets_i[i].dest_arch,
                         cdb_packets_i[i].phys_tag,
                         cdb_packets_i[i].value,
                         cdb_valid_mp_o[i], 
                         cdb_tag_rs_o[i]);
            end
        end
    end
end
*/

    // =========================================================
    // Internal signals
    // =========================================================
    logic [CDB_WIDTH-1:0]arb_grant;
    cdb_entry_t [CDB_WIDTH-1:0]selected_entries;
    logic cdb_stall;
    int used;

    // =========================================================
    // Backpressure logic
    // =========================================================
    // assign cdb_stall = !(rs_ready_i && map_ready_i);
    assign cdb_stall = '0;//###
    // =========================================================
    // Arbitration (simple priority)
    // =========================================================
    always_comb begin
        arb_grant = '0;
        used = 0 ;

        for(int i = 0 ; i < CDB_WIDTH ; i++)begin
            if(cdb_packets_i[i].valid && !cdb_stall && (used < CDB_WIDTH))begin
                arb_grant[i] = 1'b1;
                used++;
            end
        end
    end

    // =========================================================
    // Select entries that will be broadcast
    // =========================================================
    always_comb begin
        for(int j = 0; j < CDB_WIDTH ; j++)begin
            if(arb_grant[j])begin
                selected_entries[j] = cdb_packets_i[j];
            end else begin
                selected_entries[j] = '0;
            end
        end
    end

    // =========================================================
    // Output register stage (timing alignment)
    // =========================================================

    always_comb begin
        cdb_valid_rs_o      = '0;
        cdb_valid_mp_o      = '0;
        cdb_tag_rs_o        = '0;
        cdb_phy_tag_mp_o    = '0;
        cdb_dest_arch_mp_o  = '0;
        if (!cdb_stall)begin
            for (int k = 0; k < CDB_WIDTH; k++) begin
                cdb_valid_rs_o[k]      = selected_entries[k].valid;
                cdb_valid_mp_o[k]      = selected_entries[k].valid;
                cdb_tag_rs_o[k]        = selected_entries[k].phys_tag;
                cdb_phy_tag_mp_o[k]    = selected_entries[k].phys_tag;
                cdb_dest_arch_mp_o[k]  = selected_entries[k].dest_arch;
            end
        end
    end 




endmodule
