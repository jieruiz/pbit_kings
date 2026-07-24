`ifndef PBIT_EDGE_CONTRIB2
`define PBIT_EDGE_CONTRIB2
module pbit_edge_contrib2 (
    input  logic accept_i,
    input  logic edge_sign_i,      // 1: J = +1, 0: J = -1
    input  logic neighbor_spin_i,  // 1: s = +1, 0: s = -1

    output logic signed [1:0] contrib_o
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
                default: contrib_o = 2'sd0;
            endcase
        end
    end
endmodule
`endif