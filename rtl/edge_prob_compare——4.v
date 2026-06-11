`timescale 1ns / 1ps

module edge_prob_compare4 (
    input  wire [3:0] rand4_i,
    input  wire [3:0] prob4_i,
    input  wire       valid_i,
    output wire       accept_o
);

    wire cmp_accept;

    assign cmp_accept =
        (prob4_i == 4'hF) ? 1'b1 :
        (rand4_i < prob4_i);

    assign accept_o = valid_i ? cmp_accept : 1'b0;

endmodule