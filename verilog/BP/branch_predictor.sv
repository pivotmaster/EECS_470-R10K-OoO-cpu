`include "sys_defs.svh"

module branch_predictor (
    input  logic clock,
    input  logic reset,

    // Input from Fetch stage
    input ADDR [`FETCH_WIDTH-1:0] if_pc_i,
    input INST [`FETCH_WIDTH-1:0] inst_i,
    input logic [`FETCH_WIDTH-1:0] if_valid_i,


    // Input from Execution stage
    input logic [`FETCH_WIDTH-1:0] ex_is_branch_i,
    input logic [`FETCH_WIDTH-1:0] ex_branch_taken_i,
    input ADDR [`FETCH_WIDTH-1:0] ex_branch_pc_i,
    input ADDR [`FETCH_WIDTH-1:0] ex_target_pc_i,
    input logic [`FETCH_WIDTH-1:0] [`HISTORY_BITS-1:0] ex_history_i, 
    input logic [`FETCH_WIDTH-1:0] mispredict_i,

    // output
    output ADDR [`FETCH_WIDTH-1:0] next_pc_o,
    output logic take_branch, //predicted taken
    output logic [`FETCH_WIDTH-1:0] [`HISTORY_BITS-1:0] history_o //predicted history
);
    //predecode signals
    logic [`FETCH_WIDTH-1:0] cond_branch, uncond_branch;
    logic [`FETCH_WIDTH-1:0] jump, jump_back;

    //Return Address Stack signals
    ADDR link_pc, return_pc;
    logic [`FETCH_WIDTH-1:0] jump_psel_gnt, jump_back_psel_gnt, branch_psel_gnt;
    logic push, pop;

    //BTB signals
    logic [`FETCH_WIDTH-1:0] btb_hit;
    ADDR [`FETCH_WIDTH-1:0] pred_pc;

    //Gshare signals
    logic [`FETCH_WIDTH-1:0] pred_taken;
    logic [`FETCH_WIDTH-1:0] branch_req;

    always_comb begin
        for (int i = 0; i < `FETCH_WIDTH; i++) begin
            branch_req[i]   = 1'b0;
            if (if_valid_i[i]) begin
                if (jump_back[i]) begin
                    branch_req[i] = 1'b1;
                end else if (uncond_branch[i] || jump[i]) begin
                    branch_req[i] = btb_hit[i];
                end else if (cond_branch[i]) begin
                    branch_req[i]   = btb_hit[i] & pred_taken[i];
                end
            end
        end
    end

    psel_gen #(
         .WIDTH(`FETCH_WIDTH),
         .REQS(1) // We only want the FIRST valid branch
    ) branch_psel (
         .req(branch_req),
         .gnt_bus(branch_psel_gnt)
    );

    assign take_branch = |branch_psel_gnt;

    //next PC logic
    always_comb begin
        for (int i = 0; i < `FETCH_WIDTH; i++) begin
            next_pc_o[i] = if_pc_i[i] + 4;

            if (jump_back_psel_gnt[i]) begin
                next_pc_o[i] = return_pc;
            end else if (btb_hit[i] && (pred_taken[i] | jump_psel_gnt[i])) begin             
                next_pc_o[i] = pred_pc[i];
            end
        end
    end

    //RAS logic
    always_comb begin
        push    = 1'b0;
        pop     = 1'b0;
        link_pc = '0;

        if (|jump_psel_gnt) begin
            push    = 1'b1;
            for (int i = 0; i < `FETCH_WIDTH; i++) begin
                if(jump_psel_gnt[i]) begin
                    link_pc = if_pc_i[i]; // Only the first jump matter
                end
            end
        end

        if (|jump_back_psel_gnt) begin
            pop = 1'b1;
        end
    end

    psel_gen #(
         .WIDTH(`FETCH_WIDTH),
         .REQS(1)
    ) jump_psel (
         .req(jump),
         .gnt_bus(jump_psel_gnt)
    );

    psel_gen #(
         .WIDTH(`FETCH_WIDTH),
         .REQS(1)
    ) jump_back_psel (
         .req(jump_back),
         .gnt_bus(jump_back_psel_gnt)
    );


    btb btb_0 (
        .clock(clock),
        .reset(reset),
        .if_pc_i(if_pc_i),
        .ex_pc_i(ex_branch_pc_i),
        .ex_target_i(ex_target_pc_i),
        .is_branch_ex_i(ex_is_branch_i),
        .hit_o(btb_hit),
        .pred_pc_o(pred_pc)
    );

    gshare gshare_0 (
        .clock(clock),
        .reset(reset),
        .if_pc_i(if_pc_i),
        .if_is_branch_i(cond_branch),
        .ex_is_branch_i(ex_is_branch_i),
        .ex_branch_taken_i(ex_branch_taken_i),
        .ex_branch_pc_i(ex_branch_pc_i),
        .ex_history_i(ex_history_i),
        .mispredict_i(mispredict_i),

        .predict_o(pred_taken),
        .history_o(history_o)
    );

    ras ras_0 (
        .clock(clock),
        .reset(reset),
        .pc_in(link_pc),
        .push(push),
        .pop(pop),
        .return_pc_o(return_pc)
    );

    for (genvar i = 0; i < `FETCH_WIDTH; i++) begin : pre_decoders
        pre_decoder pre_decode (
            //Input
            .inst(inst_i[i]),
            .valid(if_valid_i[i]),
            //Output
            .cond_branch(cond_branch[i]),
            .uncond_branch(uncond_branch[i]),
            .jump(jump[i]),
            .jump_back(jump_back[i])
        );
    end

    always_comb begin
        for (int i = 0; i < `FETCH_WIDTH; i++)begin
            $display("branch predictor%d, pred_pc = %0h, next_pc_o = %0h, pc_in = %0h, inst = %b valid = %b,return_pc=%0h, %0d, is_branch: %b, sig: %b, pred_taken = %b, ex_taken = %b",i,pred_pc[i],  next_pc_o[i], if_pc_i[i], inst_i[i], if_valid_i[i], return_pc, take_branch, ex_is_branch_i, (btb_hit[i] && (pred_taken[i] | jump_psel_gnt[i])), pred_taken, ex_branch_taken_i[i]);
            $display("branch predictor_history=%b", history_o);
        end
    end

endmodule