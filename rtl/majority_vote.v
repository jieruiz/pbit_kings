`timescale 1ns / 1ps

module majority_vote #(
    parameter N_TRIAL = 5
)(
    input  wire [N_TRIAL-1:0] votes_i,
    input  wire               last_vote_i,
    output reg                majority_o,
    output reg  [3:0]         plus_count_o
);

    integer k;

    always @(*) begin
        plus_count_o = 4'd0;

        for (k = 0; k < N_TRIAL; k = k + 1) begin
            plus_count_o = plus_count_o + votes_i[k];
        end

        if ((plus_count_o << 1) > N_TRIAL)
            majority_o = 1'b1;
        else if ((plus_count_o << 1) < N_TRIAL)
            majority_o = 1'b0;
        else
            majority_o = last_vote_i;
    end

endmodule