`timescale 1ns/1ps
`include "def.svh"

module issue_logic #(
    parameter int unsigned RS_DEPTH        = 64, //RS entry numbers
    parameter int unsigned DISPATCH_WIDTH  = 1,
    parameter int unsigned ISSUE_WIDTH     = 1,
    parameter int unsigned CDB_WIDTH       = 1,
    parameter int unsigned PHYS_REGS       = 128,
    parameter int unsigned OPCODE_N        = 8,  //number of opcodes
    parameter int unsigned FU_NUM          = 6,  // how many different FU
    parameter int unsigned MAX_FIFO_DEPTH  = 4,  // Remaining FIFO space for each FU
    parameter int unsigned XLEN            = 64,
    parameter int ALU_COUNT   = 1,
    parameter int MUL_COUNT   = 1,
    parameter int LOAD_COUNT  = 1,
    parameter int BR_COUNT    = 1
)(
    input  logic                                                  clock,
    input  logic                                                  reset,

    // =========================================================
    // RS -> Issue Logic
    // =========================================================
    input  rs_entry_t    [RS_DEPTH-1:0]             rs_entries_i,
    input  logic         [RS_DEPTH-1:0]             rs_ready_i,
    input  fu_type_e                                fu_types_i [RS_DEPTH],

    output logic         [RS_DEPTH-1:0]             issue_enable_o, // which rs slot is going to be issued

    // =========================================================
    // FU <-> Issue logic
    // =========================================================
    //input   logic          [$clog2(MAX_FIFO_DEPTH)-1:0] fu_free_slots [FU_NUM], // Remaining FIFO space for each FU
    input logic   alu_ready_i  [ALU_COUNT],
    input logic   mul_ready_i  [MUL_COUNT],
    input logic   load_ready_i [LOAD_COUNT],
    input logic   br_ready_i   [BR_COUNT],

    output  issue_packet_t alu_req_o  [ALU_COUNT], // pkts to ALU 
    output  issue_packet_t mul_req_o  [MUL_COUNT],
    output  issue_packet_t load_req_o [LOAD_COUNT],
    output  issue_packet_t br_req_o   [BR_COUNT]
);

    // =========================================================
    // Grant Issue permission to RS entry (by issue selector)
    // =========================================================
    // Select who can issue ('issue_enable')
    logic [RS_DEPTH-1:0] issue_sel_out;
    logic [RS_DEPTH-1:0] issue_enable_o_next; // internal signal
    assign issue_enable_o_next = issue_sel_out;

    issue_selector #(
        .RS_DEPTH(RS_DEPTH),
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .ALU_COUNT(ALU_COUNT),
        .MUL_COUNT(MUL_COUNT),
        .LOAD_COUNT(LOAD_COUNT),
        .BR_COUNT(BR_COUNT)
    )issue_sel(
        .alu_ready_i(alu_ready_i),
        .mul_ready_i(mul_ready_i),
        .load_ready_i(load_ready_i),
        .br_ready_i(br_ready_i),

        .rs_ready_vec(rs_ready_i),
        .fu_types(fu_types_i),
        .issue_rs_entry(issue_sel_out) //第幾個Rs entry可以issue
    );

    // Prevent issue_enable_o -> affect RS (input of issue selector) at the same cycle
    always_ff @( posedge clock or posedge reset) begin 
        //$display("issue_enable_o_ = %b | issue_enable_o_next = %b", issue_enable_o, issue_enable_o_next);
        if (reset) begin
            issue_enable_o <= '0;
        end else begin
            issue_enable_o <= issue_enable_o_next;
        end
    end

    // =========================================================
    // Issue logic -> FU
    // =========================================================
    // Packets that sent to the FIFOs
    issue_packet_t [ISSUE_WIDTH-1:0]   issue_pkts    ;    // packets to FIFOs
    int issue_slot;

    // Generate Issue Packets
    always_comb begin : issue_output
        issue_slot = 0;


        alu_req_o[0]  = '0;
        mul_req_o[0]  = '0;
        load_req_o[0] = '0;
        br_req_o[0]   = '0;

        for (int j = 0; j < ISSUE_WIDTH; j++) begin
            issue_pkts[j].valid = 0;
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_sel_out[i]) begin
                //$display("rob=%d", rs_entries_i[i].rob_idx);
                issue_pkts[issue_slot].valid     = 1;
                issue_pkts[issue_slot].rob_idx   = rs_entries_i[i].rob_idx;
                issue_pkts[issue_slot].fu_type   = rs_entries_i[i].fu_type;
                issue_pkts[issue_slot].dest_tag  = rs_entries_i[i].dest_tag;
                issue_pkts[issue_slot].src1_val  = rs_entries_i[i].src1_tag;
                issue_pkts[issue_slot].src2_val  = rs_entries_i[i].src2_tag;

                case (issue_pkts[issue_slot].fu_type)
                
                    2'b00: if (alu_ready_i[0]) begin
                       // $display("rs_entries_i[i].fu_type %d", rs_entries_i[i].fu_type);
                        //$display("issue_pkts[issue_slot].fu_type %d", issue_pkts[issue_slot].fu_type);
                       // $display("alu_rob=%d", issue_pkts[issue_slot].rob_idx);
                        alu_req_o[0] = issue_pkts[issue_slot];
                        //$display("alu_req_o_rob=%d", alu_req_o[0].rob_idx);
                    end
                    2'b01: if (mul_ready_i[0]) begin
                        mul_req_o[0] = issue_pkts[issue_slot];
                    end
                    2'b10: if (load_ready_i[0]) begin
                        load_req_o[0] = issue_pkts[issue_slot];
                    end
                    2'b11: if (br_ready_i[0]) begin
                        br_req_o[0] = issue_pkts[issue_slot];
                    end
                    default: ;
                endcase

                issue_slot++;
                if (issue_slot >= ISSUE_WIDTH) break;
            end 
        end

end

  // =========================================================
  // DEBUG
  // =========================================================
  
    task automatic show_rs_input(int cyc);
        $display("[cycle]:", cyc);
        for (int i = 0; i < RS_DEPTH; i++) begin
        $display("Entry %0d: ready=%b, fu=%p, valid=%b, rob_idx=%0d, fu_type=%0d, dest_tag=%0d, src1_tag=%0d(%b), src2_tag=%0d(%b)", 
            i, rs_ready_i[i], rs_entries_i[i].valid, fu_types_i[i], rs_entries_i[i].rob_idx, rs_entries_i[i].fu_type, 
            rs_entries_i[i].dest_tag, rs_entries_i[i].src1_tag, rs_entries_i[i].src1_ready,
            rs_entries_i[i].src2_tag, rs_entries_i[i].src2_ready);
        end
    endtask

    task automatic test_grant_vector(int cyc);
            $display("[cycle]:", cyc);
            for (int j = 0; j < RS_DEPTH; j++) begin
                $write("%b", issue_sel_out[j]);
            end
            $write("\n");
        
    endtask

    task automatic test_reqs(int cyc);
        $display("cycle= %d",cyc);
        $display("alu_req_o");
        $display("rob=%d | dest_tag =%d | fu=%p",alu_req_o[0].rob_idx, alu_req_o[0].dest_tag, alu_req_o[0].fu_type);
        $display("mul_req_o");
        $display("rob=%d | dest_tag =%d| fu=%p",mul_req_o[0].rob_idx, mul_req_o[0].dest_tag,mul_req_o[0].fu_type);
        $display("load_req_o");
        $display("rob=%d | dest_tag =%d| fu=%p",load_req_o[0].rob_idx, load_req_o[0].dest_tag,load_req_o[0].fu_type);
        $display("br_req_o");
        $display("rob=%d | dest_tag =%d| fu=%p",br_req_o[0].rob_idx, br_req_o[0].dest_tag,br_req_o[0].fu_type);
    endtask

        

task automatic test_issue_selector(input int cyc);
    $write("[Cycle=%0d]\n", cyc);

    // ---- ALU ready ----
    $write("  alu_ready_i   = ");
    for (int i = 0; i < ALU_COUNT; i++)
        $write("%b", alu_ready_i[i]);
    $write("\n");

    // ---- MUL ready ----
    $write("  mul_ready_i   = ");
    for (int i = 0; i < MUL_COUNT; i++)
        $write("%b", mul_ready_i[i]);
    $write("\n");

    // ---- LOAD ready ----
    $write("  load_ready_i  = ");
    for (int i = 0; i < LOAD_COUNT; i++)
        $write("%b", load_ready_i[i]);
    $write("\n");

    // ---- BR ready ----
    $write("  br_ready_i    = ");
    for (int i = 0; i < BR_COUNT; i++)
        $write("%b", br_ready_i[i]);
    $write("\n");

    // ---- RS ready vector ----
    $write("  rs_ready_vec  = ");
    for (int j = 0; j < RS_DEPTH; j++)
        $write("%b", rs_ready_i[j]);
    $write("\n");

    // ---- FU types ----
    $write("  fu_types_i    = ");
    for (int j = 0; j < RS_DEPTH; j++)
        $write("%p", fu_types_i[j]); 
    $write("\n");

    // ---- Issue output ----
    $write("  issue_enable_o_next = ");
    for (int j = 0; j < RS_DEPTH; j++)
        $write("%b", issue_enable_o_next[j]);
    $write("\n\n");

    // ---- Issue output ----
    $write("  issue_enable_o = ");
    for (int j = 0; j < RS_DEPTH; j++)
        $write("%b", issue_enable_o[j]);
    $write("\n\n");
endtask

task automatic show_issue_output(input int cyc);
    $write("\n================= [Cycle %0d] Issue Output =================\n", cyc);

    // ---- ALU requests ----
    $write("ALU_REQ:\n");
    for (int i = 0; i < ALU_COUNT; i++) begin
        $write("  [%0d] valid=%0b | rob=%0d | dest=%0d | src1=%0d | src2=%0d\n",
               i,
               alu_req_o[i].valid,
               alu_req_o[i].rob_idx,
               alu_req_o[i].dest_tag,
               alu_req_o[i].src1_val,
               alu_req_o[i].src2_val);
    end

    // ---- MUL requests ----
    $write("MUL_REQ:\n");
    for (int i = 0; i < MUL_COUNT; i++) begin
        $write("  [%0d] valid=%0b | rob=%0d | dest=%0d | src1=%0d | src2=%0d\n",
               i,
               mul_req_o[i].valid,
               mul_req_o[i].rob_idx,
               mul_req_o[i].dest_tag,
               mul_req_o[i].src1_val,
               mul_req_o[i].src2_val);
    end

    // ---- LOAD requests ----
    $write("LOAD_REQ:\n");
    for (int i = 0; i < LOAD_COUNT; i++) begin
        $write("  [%0d] valid=%0b | rob=%0d | dest=%0d | src1=%0d | src2=%0d\n",
               i,
               load_req_o[i].valid,
               load_req_o[i].rob_idx,
               load_req_o[i].dest_tag,
               load_req_o[i].src1_val,
               load_req_o[i].src2_val);
    end

    // ---- BRANCH requests ----
    $write("BR_REQ:\n");
    for (int i = 0; i < BR_COUNT; i++) begin
        $write("  [%0d] valid=%0b | rob=%0d | dest=%0d | src1=%0d | src2=%0d\n",
               i,
               br_req_o[i].valid,
               br_req_o[i].rob_idx,
               br_req_o[i].dest_tag,
               br_req_o[i].src1_val,
               br_req_o[i].src2_val);
    end

    $write("=============================================================\n\n");
endtask

  int cycle_count;
  always_ff @(posedge clock) begin
    if (reset)  
        cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
      //show_rs_input(cycle_count);
      //test_grant_vector(cycle_count);
      //test_issue_selector(cycle_count);
      show_issue_output(cycle_count);
      //test_reqs(cycle_count);
    
  end

endmodule


