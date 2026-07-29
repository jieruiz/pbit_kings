`ifndef EDGE_COMPARE8_NAMED
`define EDGE_COMPARE8_NAMED
import pbit_pkg::*;
module edge_compare8_named (
    input logic [NODE_SEED_WIDTH-1:0] edge_rand32_i,

    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_i,

    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_i,

    output logic accept_n_o,
    output logic accept_ne_o,
    output logic accept_e_o,
    output logic accept_se_o,
    output logic accept_s_o,
    output logic accept_sw_o,
    output logic accept_w_o,
    output logic accept_nw_o
);

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_n (
        .rand_i  (edge_rand32_i[0+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_n_i),
        .valid_i  (edge_valid_n_i),
        .accept_o (accept_n_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_ne (
        .rand_i  (edge_rand32_i[4+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_ne_i),
        .valid_i  (edge_valid_ne_i),
        .accept_o (accept_ne_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_e (
        .rand_i  (edge_rand32_i[8+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_e_i),
        .valid_i  (edge_valid_e_i),
        .accept_o (accept_e_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_se (
        .rand_i  (edge_rand32_i[12+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_se_i),
        .valid_i  (edge_valid_se_i),
        .accept_o (accept_se_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_s (
        .rand_i  (edge_rand32_i[16+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_s_i),
        .valid_i  (edge_valid_s_i),
        .accept_o (accept_s_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_sw (
        .rand_i  (edge_rand32_i[20+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_sw_i),
        .valid_i  (edge_valid_sw_i),
        .accept_o (accept_sw_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_w (
        .rand_i  (edge_rand32_i[24+:EDGE_CFG_EDGE_PROB_WIDTH]),
        .prob_i  (edge_prob_w_i),
        .valid_i  (edge_valid_w_i),
        .accept_o (accept_w_o)
    );

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_cmp_nw (
        .rand_i  ({edge_rand32_i[0+:(EDGE_CFG_EDGE_PROB_WIDTH-4)], edge_rand32_i[31:28]}),
        .prob_i  (edge_prob_nw_i),
        .valid_i  (edge_valid_nw_i),
        .accept_o (accept_nw_o)
    );

endmodule
`endif