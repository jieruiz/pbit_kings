`ifndef MAJORITY_VOTE
`define MAJORITY_VOTE
import pbit_pkg::*;
module majority_vote (
    input  logic [NUM_MAJORITY_MAX-1:0]   votes_i,
    input  logic                          majority_en_i,  
    input  logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,
    output logic                          majority_o
);
    localparam COUNT_W = $clog2(NUM_MAJORITY_MAX+1);
    logic [COUNT_W-1:0]          count_one_w;
    logic [COUNT_W:0]            count_one_double_w;
    logic [COUNT_W-1:0]          num_majority_act_w;
    logic [NUM_MAJORITY_MAX-1:0] votes_w;

    assign votes_w = {NUM_MAJORITY_MAX{majority_en_i}} & votes_i;
    assign num_majority_act_w = num_majority_i + 1;
    assign count_one_double_w = {count_one_w, 1'b0};
    one_counter #(
        .WIDTH(NUM_MAJORITY_MAX),
        .COUNT_W(COUNT_W)
    ) one_counter_inst (
        .data_i(votes_w),
        .count_o(count_one_w)
    );

    always @(*) begin
        if(!majority_en_i)
            majority_o = 1'b0;
        else if(count_one_double_w < num_majority_act_w)
            majority_o = 1'b0;
        else if (count_one_double_w > num_majority_act_w)
            majority_o = 1'b1;
        else
            majority_o = votes_w[0];
    end

endmodule
`endif