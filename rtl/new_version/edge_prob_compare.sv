`ifndef EDGE_PROB_COMPARE
`define EDGE_PROB_COMPARE
module edge_prob_compare #(
    parameter WIDTH = 8
)(
    input  logic [WIDTH-1:0] rand_i,
    input  logic [WIDTH-1:0] prob_i,
    input  logic             valid_i,
    output logic             accept_o
);

    logic cmp_accept;

    assign cmp_accept = (rand_i <= prob_i);

    assign accept_o = valid_i ? cmp_accept : 1'b0;

endmodule
`endif