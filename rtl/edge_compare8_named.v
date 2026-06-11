`timescale 1ns / 1ps

module edge_compare8_named (
    input wire [31:0] edge_rand32_i,

    input wire [3:0] edge_prob_n_i,
    input wire [3:0] edge_prob_ne_i,
    input wire [3:0] edge_prob_e_i,
    input wire [3:0] edge_prob_se_i,
    input wire [3:0] edge_prob_s_i,
    input wire [3:0] edge_prob_sw_i,
    input wire [3:0] edge_prob_w_i,
    input wire [3:0] edge_prob_nw_i,

    input wire edge_valid_n_i,
    input wire edge_valid_ne_i,
    input wire edge_valid_e_i,
    input wire edge_valid_se_i,
    input wire edge_valid_s_i,
    input wire edge_valid_sw_i,
    input wire edge_valid_w_i,
    input wire edge_valid_nw_i,

    output wire accept_n_o,
    output wire accept_ne_o,
    output wire accept_e_o,
    output wire accept_se_o,
    output wire accept_s_o,
    output wire accept_sw_o,
    output wire accept_w_o,
    output wire accept_nw_o
);

    edge_prob_compare4 u_cmp_n (
        .rand4_i  (edge_rand32_i[3:0]),
        .prob4_i  (edge_prob_n_i),
        .valid_i  (edge_valid_n_i),
        .accept_o (accept_n_o)
    );

    edge_prob_compare4 u_cmp_ne (
        .rand4_i  (edge_rand32_i[7:4]),
        .prob4_i  (edge_prob_ne_i),
        .valid_i  (edge_valid_ne_i),
        .accept_o (accept_ne_o)
    );

    edge_prob_compare4 u_cmp_e (
        .rand4_i  (edge_rand32_i[11:8]),
        .prob4_i  (edge_prob_e_i),
        .valid_i  (edge_valid_e_i),
        .accept_o (accept_e_o)
    );

    edge_prob_compare4 u_cmp_se (
        .rand4_i  (edge_rand32_i[15:12]),
        .prob4_i  (edge_prob_se_i),
        .valid_i  (edge_valid_se_i),
        .accept_o (accept_se_o)
    );

    edge_prob_compare4 u_cmp_s (
        .rand4_i  (edge_rand32_i[19:16]),
        .prob4_i  (edge_prob_s_i),
        .valid_i  (edge_valid_s_i),
        .accept_o (accept_s_o)
    );

    edge_prob_compare4 u_cmp_sw (
        .rand4_i  (edge_rand32_i[23:20]),
        .prob4_i  (edge_prob_sw_i),
        .valid_i  (edge_valid_sw_i),
        .accept_o (accept_sw_o)
    );

    edge_prob_compare4 u_cmp_w (
        .rand4_i  (edge_rand32_i[27:24]),
        .prob4_i  (edge_prob_w_i),
        .valid_i  (edge_valid_w_i),
        .accept_o (accept_w_o)
    );

    edge_prob_compare4 u_cmp_nw (
        .rand4_i  (edge_rand32_i[31:28]),
        .prob4_i  (edge_prob_nw_i),
        .valid_i  (edge_valid_nw_i),
        .accept_o (accept_nw_o)
    );

endmodule