// SIMULATION ONLY: logic connectivity, not pad delays, ESD or electrical signoff.
module TIEHIX1_9TSVT(output wire Y); assign Y = 1'b1; endmodule
module TIELOX1_9TSVT(output wire Y); assign Y = 1'b0; endmodule
module PDISDU(input wire PAD, PU, PD, IE, ST, output wire C);
    assign C = IE ? PAD : 1'b0;
endmodule
module PDBSDU(inout wire PAD, input wire OE, PU, PD, A, S0, S1, S2, IE, ST,
              output wire C);
    assign PAD = OE ? A : 1'bz;
    assign C = IE ? PAD : 1'b0;
endmodule
