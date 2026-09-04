`ifndef MAJORITY_VOTE
`define MAJORITY_VOTE
import pbit_pkg::*;
module majority_vote (
    input  logic [NUM_MAJORITY_WIDTH:0]   spin_sum_i,
    input  logic                          majority_en_i,  
    input  logic [NUM_MAJORITY_WIDTH:0]   num_majority_act_i,
    output logic                          majority_o
);

    always @(*) begin
        if(!majority_en_i)
            majority_o = 1'b0;
        else if({spin_sum_i, 1'b0} < num_majority_act_i)
            majority_o = 1'b0;
        else if ({spin_sum_i, 1'b0} > num_majority_act_i)
            majority_o = 1'b1;
        else
            majority_o = spin_sum_i[0];
    end

endmodule
`endif