`timescale 1ns / 1ps

module pbit_prob_compare16 (
    input  wire [15:0] rand16_i,
    input  wire [15:0] prob16_i,
    output wire        accept_o
);

    assign accept_o =
        (prob16_i == 16'h0000) ? 1'b0 :
        (rand16_i <= prob16_i);

endmodule