`ifndef MAC
`define MAC
import pbit_pkg::*;
module mac (
    input logic clk,
    input logic [SEED_WIDTH-1:0] rnd32_i,

    // Unit cell selects node r or r+4 before this shared datapath.
    // Lanes 0..3: opposite-column nodes, top to bottom.
    // Lane 4: up/left; lane 5: down/right. Missing edges have valid=0.
    input logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign_i,
    input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_i,
    input logic [MAC_EDGE_NUM-1:0] neighbor_spin_i,
    input logic [MAC_EDGE_NUM-1:0] edge_valid_i,
    input logic [MAC_EDGE_NUM-1:0] edge_sign_i,
    input wire [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_i [0:MAC_EDGE_NUM-1],

    input logic macsum_en_i,
    output logic signed [MACSUM_WIDTH-1:0] macsum_o
);
    logic [MAC_EDGE_NUM-1:0] accept_w;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_rand_w;
    logic accept_bias_w;
    logic signed [1:0] contrib_w [0:MAC_EDGE_NUM];
    logic signed [2:0] pair_w [0:2];
    logic signed [MACSUM_WIDTH-1:0] half_w [0:1];
    logic signed [MACSUM_WIDTH-1:0] macsum_d;
    logic [MACSUM_WIDTH-1:0] macsum_q;

    edge_compare6 u_edge_compare6 (
        .edge_rand32_i (rnd32_i),
        .edge_prob_i   (edge_prob_i),
        .edge_valid_i  (edge_valid_i),
        .accept_o      (accept_w)
    );
    // Preserve the original bias random-bit mapping and <= comparison.
    assign bias_rand_w = {rnd32_i[12], rnd32_i[10], rnd32_i[8],
                          rnd32_i[6], rnd32_i[4], rnd32_i[2], rnd32_i[0]};
    edge_prob_compare #(
        .WIDTH(NODE_CFG_BIAS_PROB_WIDTH)
    ) u_bias_prob_compare (
        .rand_i   (bias_rand_w),
        .prob_i   (bias_prob_i),
        .valid_i  (1'b1),
        .accept_o (accept_bias_w)
    );

    genvar edge_idx;
    generate
        for (edge_idx = 0; edge_idx < MAC_EDGE_NUM; edge_idx = edge_idx + 1) begin : GEN_EDGE_CONTRIB
            pbit_edge_contrib2 u_edge_contrib (
                .accept_i        (accept_w[edge_idx]),
                .edge_sign_i     (edge_sign_i[edge_idx]),
                .neighbor_spin_i (neighbor_spin_i[edge_idx]),
                .contrib_o       (contrib_w[edge_idx])
            );
        end
    endgenerate

    pbit_edge_contrib2 u_bias_contrib (
        .accept_i        (accept_bias_w),
        .edge_sign_i     (bias_sign_i),
        .neighbor_spin_i (1'b1),
        .contrib_o       (contrib_w[MAC_EDGE_NUM])
    );

    // Balanced seven-term tree: pairs need 3 bits; remaining sums need 4.
    // Bias enters the second level instead of adding a fourth serial level.
    genvar pair_idx;
    generate
        for (pair_idx = 0; pair_idx < 3; pair_idx = pair_idx + 1) begin : GEN_PAIR_SUM
            assign pair_w[pair_idx] =
                $signed({contrib_w[2*pair_idx][1], contrib_w[2*pair_idx]}) +
                $signed({contrib_w[2*pair_idx+1][1], contrib_w[2*pair_idx+1]});
        end
    endgenerate
    assign half_w[0] = $signed({pair_w[0][2], pair_w[0]}) +
                       $signed({pair_w[1][2], pair_w[1]});
    assign half_w[1] = $signed({pair_w[2][2], pair_w[2]}) +
                       $signed({{(MACSUM_WIDTH-2){contrib_w[6][1]}}, contrib_w[6]});
    assign macsum_d = half_w[0] + half_w[1];
    assign macsum_o = $signed(macsum_q);

    // Preserve enabled-register behavior and one-clock latency; no reset.
    dffe #(.WIDTH(MACSUM_WIDTH)
    ) macsum_ff (
        .clk  (clk),
        .en_i (macsum_en_i),
        .d_i  ($unsigned(macsum_d)),
        .q_o  (macsum_q)
    );
endmodule
`endif
