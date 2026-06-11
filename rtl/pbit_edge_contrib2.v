`timescale 1ns / 1ps

module pbit_edge_contrib2 (
    input  wire accept_i,
    input  wire edge_sign_i,      // 1: J = +1, 0: J = -1
    input  wire neighbor_spin_i,  // 1: s = +1, 0: s = -1

    output reg signed [1:0] contrib_o
);

    always @(*) begin
        if (!accept_i) begin
            contrib_o = 2'sd0;
        end else begin
            case ({edge_sign_i, neighbor_spin_i})
                2'b11: contrib_o =  2'sd1;  // +J * +s
                2'b10: contrib_o = -2'sd1;  // +J * -s
                2'b01: contrib_o = -2'sd1;  // -J * +s
                2'b00: contrib_o =  2'sd1;  // -J * -s
            endcase
        end
    end

endmodule