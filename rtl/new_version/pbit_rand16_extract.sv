`ifndef PBIT_RAND16_EXTRACT
`define PBIT_RAND16_EXTRACT
module pbit_rand16_extract (
    input  logic [31:0] rand32_i,
    output logic [15:0] rand16_o
);

    assign rand16_o[0]  = rand32_i[23] ^ rand32_i[28];
    assign rand16_o[1]  = rand32_i[9]  ^ rand32_i[22];
    assign rand16_o[2]  = rand32_i[5]  ^ rand32_i[14];
    assign rand16_o[3]  = rand32_i[11] ^ rand32_i[18];

    assign rand16_o[4]  = rand32_i[19] ^ rand32_i[30];
    assign rand16_o[5]  = rand32_i[21] ^ rand32_i[29];
    assign rand16_o[6]  = rand32_i[17] ^ rand32_i[26];
    assign rand16_o[7]  = rand32_i[10] ^ rand32_i[24];

    assign rand16_o[8]  = rand32_i[16] ^ rand32_i[28];
    assign rand16_o[9]  = rand32_i[2]  ^ rand32_i[15];
    assign rand16_o[10] = rand32_i[6]  ^ rand32_i[25];
    assign rand16_o[11] = rand32_i[8]  ^ rand32_i[27];

    assign rand16_o[12] = rand32_i[12] ^ rand32_i[31];
    assign rand16_o[13] = rand32_i[0]  ^ rand32_i[7];
    assign rand16_o[14] = rand32_i[20] ^ rand32_i[24];
    assign rand16_o[15] = rand32_i[4]  ^ rand32_i[18];

endmodule
`endif