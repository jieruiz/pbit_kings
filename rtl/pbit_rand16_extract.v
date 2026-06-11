`timescale 1ns / 1ps

module pbit_rand16_extract (
    input  wire [31:0] rand32_i,
    output wire [15:0] rand16_o
);

    assign rand16_o[0]  = rand32_i[0];
    assign rand16_o[1]  = rand32_i[2];
    assign rand16_o[2]  = rand32_i[4];
    assign rand16_o[3]  = rand32_i[6];

    assign rand16_o[4]  = rand32_i[8];
    assign rand16_o[5]  = rand32_i[10];
    assign rand16_o[6]  = rand32_i[12];
    assign rand16_o[7]  = rand32_i[14];

    assign rand16_o[8]  = rand32_i[16];
    assign rand16_o[9]  = rand32_i[18];
    assign rand16_o[10] = rand32_i[20];
    assign rand16_o[11] = rand32_i[22];

    assign rand16_o[12] = rand32_i[24];
    assign rand16_o[13] = rand32_i[26];
    assign rand16_o[14] = rand32_i[28];
    assign rand16_o[15] = rand32_i[30];

endmodule
