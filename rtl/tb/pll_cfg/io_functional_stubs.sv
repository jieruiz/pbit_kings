// SIMULATION ONLY: digital connectivity, not pad delay, ESD, or SI behavior.
module PDISDU(
    input  wire PAD,
    input  wire PU,
    input  wire PD,
    input  wire IE,
    input  wire ST,
    output wire C
);
    assign C = IE ? PAD : 1'b0;
endmodule

module PDBSDU(
    inout  wire PAD,
    input  wire OE,
    input  wire PU,
    input  wire PD,
    input  wire A,
    input  wire S0,
    input  wire S1,
    input  wire S2,
    input  wire IE,
    input  wire ST,
    output wire C
);
    assign PAD = OE ? A : 1'bz;
    assign C = IE ? PAD : 1'b0;
endmodule
