`ifndef PBIT_PROB_COMPARE16
`define PBIT_PROB_COMPARE16
module pbit_prob_compare16 (
    input  logic [15:0] rand16_i,
    input  logic [15:0] prob16_i,
    output logic        accept_o
);

    assign accept_o =
        (prob16_i == 16'h0000) ? 1'b0 :
        (rand16_i <= prob16_i);

endmodule
`endif