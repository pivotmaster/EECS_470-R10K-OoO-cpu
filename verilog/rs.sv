/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  RS.sv                                               //
//                                                                     //
//  Description :        //
//                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "def.svh"

module RS #(
    parameter int unsigned RS_DEPTH        = 64, //RS entry numbers
    parameter int unsigned DISPATCH_WIDTH  = 1,
    parameter int unsigned ISSUE_WIDTH     = 1,
    parameter int unsigned CDB_WIDTH       = 1,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned OPCODE_N        = 8,  //number of opcodes
    parameter int unsigned FU_NUM          = 8,  // how many different FU
    parameter int unsigned MAX_FU_PER_TYPE = 4,  // how many Fu per each FU type
    parameter int unsigned XLEN            = 64
)(
    input   logic                                                  clock,
    input   logic                                                  reset,
    input   logic                                                  flush,

    // =========================================================
    // Dispatch <-> RS
    // =========================================================
    input   logic          [DISPATCH_WIDTH-1:0]                    disp_valid_i,
    input   rs_entry_t     [DISPATCH_WIDTH-1:0]                    rs_packets_i,
    input   logic          [DISPATCH_WIDTH-1:0]                    disp_rs_rd_wen_i,     // read (I think it is whether write PRF?)

    output  logic          [$clog2(DISPATCH_WIDTH+1)-1:0]          free_slots_o,      // how many slot is free? (saturate at DISPATCH_WIDTH)
    output  logic                                                  rs_full_o,

    // =========================================================
    // CDB -> RS 
    // =========================================================
    input   logic          [CDB_WIDTH-1:0]                         cdb_valid_i, 
    input   logic          [CDB_WIDTH-1:0][$clog2(PHYS_REGS)-1:0]  cdb_tag_i,

    // =========================================================
    // RS -> Issue logic (let Issue logic control who to issue)
    // =========================================================
    input   logic          [RS_DEPTH-1:0]                          issue_enable_i,

    output  rs_entry_t     [RS_DEPTH-1:0]                          rs_entries_o,
    output  logic          [RS_DEPTH-1:0]                          rs_ready_o,  
    output  fu_type_e                                              fu_type_o [RS_DEPTH]    
); 

    // =========================================================
    // Internal control signal
    // =========================================================
    // Dispatch signal
    logic         [RS_DEPTH-1:0]             disp_enable;
    rs_entry_t    [RS_DEPTH-1:0]             rs_packets;
    logic         [RS_DEPTH-1:0]             rs_empty;

    // Issue signal
    logic         [RS_DEPTH-1:0]             rs_ready;  
    logic         [$clog2(FU_NUM)-1:0]       fu_types [RS_DEPTH];

    // Dispatch_grant_rs_slot
    logic [DISPATCH_WIDTH-1:0][RS_DEPTH-1:0] disp_grant_vec;

    // Output 
    int free_slots;
    bit rs_full;

    // =========================================================
    // Whole RS table
    // =========================================================
    genvar i;
    generate 
        for (i=0; i < RS_DEPTH; i++) begin    
            rs_single_entry  #(
                .ENTRY_ID(i),
                .PHYS_REGS(PHYS_REGS),
                .CDB_WIDTH(CDB_WIDTH)
            ) rs_entry (
                .clock(clock),
                .reset(reset),
                .flush(flush),
                .disp_enable_i(disp_enable[i]),
                .rs_packets_i(rs_packets[i]),
                .empty_o(rs_empty[i]),
                .issue_i(issue_enable_i[i]),
                .rs_single_entry_o(rs_entries_o[i]),
                .fu_type_o(fu_type_o[i]),
                .ready_o(rs_ready_o[i]),
                .cdb_valid_single_i(cdb_valid_i),
                .cdb_tag_single_i(cdb_tag_i)
            );
        end
    endgenerate

    // =========================================================
    // Dispatch packets to RS entries
    // =========================================================
    // Dispatch selector: select which rs entry to dispatch
    disp_selector  #(
        .RS_DEPTH(RS_DEPTH),
        .DISPATCH_WIDTH(DISPATCH_WIDTH)
    ) disp_sel (
        .empty_vec(rs_empty),
        .disp_valid_vec(disp_valid_i),
        .disp_grant_vec(disp_grant_vec)
    );

    // Grant input packects to its corresponding rs entry (detemrine by rs_sel)
    always_comb begin: disp_pkt
        rs_packets  = '0;
        disp_enable = '0;
        for (int i = 0; i<DISPATCH_WIDTH; i++) begin
            for (int j=0; j<RS_DEPTH; j++) begin
                if (disp_grant_vec[i][j]) begin
                    rs_packets[j]  = rs_packets_i[i]; // dispatch slot i allocates RS entry j
                    disp_enable[j] = 1'b1;
                end
            end
        end
    end

    // =========================================================
    // Check remaining free slots (report to dispatch stage)
    // =========================================================
    always_comb begin : count_free_slot
        free_slots = 0; 
        rs_full    = 1;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_empty[i] && (free_slots < DISPATCH_WIDTH) ) begin
                free_slots++;
                rs_full = 0;
            end
        end
    end

    // =========================================================
    // Output
    // =========================================================
    // assign results to output port
    assign rs_full_o    = rs_full;
    assign free_slots_o = free_slots;

  // =========================================================
  // DEBUG
  // =========================================================
    task automatic test_grant_vector(int cyc);
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            $write("[cycle] = %d, disp_grant_vec[%0d]", cyc, i);
            for (int j = 0; j < RS_DEPTH; j++) begin
                $write("%b", disp_grant_vec[i][j]);
            end
            $write("\n");
        end
    endtask

    task automatic test_dispatch_enable(int cyc);
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            $write("[cycle] = %d, disp_enable[%0d]",cyc, i);
            for (int k = 0; k < RS_DEPTH; k++) begin
                $write("%b", disp_enable[k]);
            end
            $write("\n");
        end
    endtask

  task automatic show_rs_output();
    for (int i = 0; i < RS_DEPTH; i++) begin
    $display("Entry %0d: ready=%b, valid=%b, alu_func=%0d, rob_idx=%0d, fu_type=%0d, dest_reg_idx=%0d, dest_tag=%0d, src1_tag=%0d(%b), src2_tag=%0d(%b)", 
                i, rs_ready_o[i], rs_entries_o[i].valid, rs_entries_o[i].disp_packet.alu_func, rs_entries_o[i].rob_idx, rs_entries_o[i].disp_packet.fu_type, 
                rs_entries_o[i].disp_packet.dest_reg_idx , rs_entries_o[i].dest_tag, rs_entries_o[i].src1_tag, rs_entries_o[i].src1_ready,
                rs_entries_o[i].src2_tag, rs_entries_o[i].src2_ready);
    end
  endtask

  task automatic show_disp_instr();

    for (int i = 0; i < RS_DEPTH; i++) begin
        if (disp_enable[i]) begin
             
        $display("Entry %0d: ready=%b, valid=%b, alu_func=%0d, rob_idx=%0d, fu_type=%0d, dest_reg_idx=%0d, dest_tag=%0d, src1_tag=%0d(%b), src2_tag=%0d(%b)", 
                i, rs_ready_o[i], rs_entries_o[i].valid, rs_entries_o[i].disp_packet.alu_func, rs_entries_o[i].rob_idx, rs_entries_o[i].disp_packet.fu_type, 
                rs_entries_o[i].disp_packet.dest_reg_idx , rs_entries_o[i].dest_tag, rs_entries_o[i].src1_tag, rs_entries_o[i].src1_ready,
                rs_entries_o[i].src2_tag, rs_entries_o[i].src2_ready);
         $display("");
    end
    end
  
  endtask

  int cycle_count;
  always_ff @(posedge clock) begin
    if (reset)  
        cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
      //test_grant_vector(cycle_count);
     // test_dispatch_enable(cycle_count);
      //show_rs_output();
      //show_disp_instr();
    
  end

endmodule

