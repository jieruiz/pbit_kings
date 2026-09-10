// SIMULATION ONLY. The vendor IO model does not contain core-library tie cells.
module TIEHIX1_9TSVT(output wire Y);
    assign Y = 1'b1;
endmodule

module TIELOX1_9TSVT(output wire Y);
    assign Y = 1'b0;
endmodule
