`ifndef EDGE_COMPARE6
`define EDGE_COMPARE6
import pbit_pkg::*;
module edge_compare6 (
    input logic  [SEED_WIDTH-1:0] edge_rand32_i,
    input wire   [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_i [0:MAC_EDGE_NUM-1],
    input logic  [MAC_EDGE_NUM-1:0] edge_valid_i,
    output logic [MAC_EDGE_NUM-1:0] accept_o
);
    // Original n/ne/e/se/s/sw random slices, now indexed by lane.
    genvar edge_idx;
    generate
        for (edge_idx = 0; edge_idx < MAC_EDGE_NUM; edge_idx = edge_idx + 1) begin : GEN_EDGE_COMPARE
            edge_prob_compare #(
                .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
            ) u_edge_prob_compare (
                .rand_i   (edge_rand32_i[4*edge_idx +: EDGE_CFG_EDGE_PROB_WIDTH]),
                .prob_i   (edge_prob_i[edge_idx]),
                .valid_i  (edge_valid_i[edge_idx]),
                .accept_o (accept_o[edge_idx])
            );
        end
    endgenerate
endmodule
`endif
