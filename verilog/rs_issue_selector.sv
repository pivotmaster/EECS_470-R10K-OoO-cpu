module issue_selector #(
    parameter int unsigned RS_DEPTH        = 64, // RS entry numbers
    parameter int unsigned FU_NUM          = 8,  // how many different FU
    parameter int unsigned MAX_FU_PER_TYPE = 4,  // how many Fu per each FU type
    parameter int unsigned ISSUE_WIDTH     = 2
)(
    input  logic [$clog2(MAX_FU_PER_TYPE)-1:0]      fu_status_vec [FU_NUM],
    input  logic [RS_DEPTH-1:0]                     rs_ready_vec,
    input  logic [$clog2(FU_NUM)-1:0]               fu_types [RS_DEPTH],
    output logic [RS_DEPTH-1:0]                     issue_rs_entry // rs entry that was grant to issue
);  
    logic [$clog2(MAX_FU_PER_TYPE)-1:0]             fu_remain [FU_NUM];
    int                                             issue_cnt;

    always_comb begin 
        issue_rs_entry = '0;
        issue_cnt      = '0;
        fu_remain      = fu_status_vec;

        // For each dispatch slot
        for (int i = 0; i<RS_DEPTH; i++) begin
            if (rs_ready_vec[i] && (fu_remain[fu_types[i]] > 0) && issue_cnt < ISSUE_WIDTH) begin // array[b101] = array[5];
                issue_rs_entry[i] = 1'b1;
                if (fu_remain[fu_types[i]] > 0) fu_remain[fu_types[i]]--;
                issue_cnt++;
                if (issue_cnt >= ISSUE_WIDTH)   break;
            end
        end
    end

endmodule