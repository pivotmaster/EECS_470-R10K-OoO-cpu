// =========================================================
// FU #0 = ALU0
// FU #1 = ALU1
// FU #2 = ALU2
// FU #3 = MUL
// FU #4 = LOAD
// FU #5 = BRANCH
// =========================================================
`include "def.svh"

module issue_selector #(
    parameter int unsigned RS_DEPTH    = 64,
    parameter int unsigned FU_NUM      = 6,
    parameter int unsigned ISSUE_WIDTH = 4
)(
    input  logic [FU_NUM-1:0]         fu_fifo_full,
    input  logic [RS_DEPTH-1:0]       rs_ready_vec,
    input  fu_type_e                  fu_types [RS_DEPTH],
    output logic [RS_DEPTH-1:0]       issue_rs_entry
);

    // internal combinational function
    function automatic logic [RS_DEPTH-1:0] select_comb(
        input logic [FU_NUM-1:0]      fu_full,
        input logic [RS_DEPTH-1:0]    ready_vec,
        input fu_type_e               types [RS_DEPTH]
    );
        logic [RS_DEPTH-1:0] issue_vec = '0;
        logic [FU_NUM-1:0]   tmp_fu_full = fu_full;
        int issue_cnt = 0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_cnt >= ISSUE_WIDTH) break;
            if (ready_vec[i]) begin
                case (types[i])
                    FU_ALU: begin
                        if (!tmp_fu_full[0]) begin issue_vec[i]=1; tmp_fu_full[0]=1; issue_cnt++; end
                        else if (!tmp_fu_full[1]) begin issue_vec[i]=1; tmp_fu_full[1]=1; issue_cnt++; end
                        else if (!tmp_fu_full[2]) begin issue_vec[i]=1; tmp_fu_full[2]=1; issue_cnt++; end
                    end
                    FU_MUL:    if (!tmp_fu_full[3]) begin issue_vec[i]=1; tmp_fu_full[3]=1; issue_cnt++; end
                    FU_LOAD:   if (!tmp_fu_full[4]) begin issue_vec[i]=1; tmp_fu_full[4]=1; issue_cnt++; end
                    FU_BRANCH: if (!tmp_fu_full[5]) begin issue_vec[i]=1; tmp_fu_full[5]=1; issue_cnt++; end
                    default: ;
                endcase
            end
        end
        return issue_vec;
    endfunction

    // continuous assignment → single delta evaluate
    assign issue_rs_entry = select_comb(fu_fifo_full, rs_ready_vec, fu_types);

endmodule

