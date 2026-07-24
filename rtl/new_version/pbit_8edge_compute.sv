`ifndef PBIT_8EDGE_COMPUTE
`define PBIT_8EDGE_COMPUTE
import pbit_pkg::*;
module pbit_8edge_compute (
    input logic accept_n_i,
    input logic accept_ne_i,
    input logic accept_e_i,
    input logic accept_se_i,
    input logic accept_s_i,
    input logic accept_sw_i,
    input logic accept_w_i,
    input logic accept_nw_i,

    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_i,

    input logic neighbor_spin_n_i,
    input logic neighbor_spin_ne_i,
    input logic neighbor_spin_e_i,
    input logic neighbor_spin_se_i,
    input logic neighbor_spin_s_i,
    input logic neighbor_spin_sw_i,
    input logic neighbor_spin_w_i,
    input logic neighbor_spin_nw_i,

    output logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] h_sum_o
);

    logic signed [1:0] c_n;
    logic signed [1:0] c_ne;
    logic signed [1:0] c_e;
    logic signed [1:0] c_se;
    logic signed [1:0] c_s;
    logic signed [1:0] c_sw;
    logic signed [1:0] c_w;
    logic signed [1:0] c_nw;

    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_n_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_ne_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_e_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_se_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_s_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_sw_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_w_ext;
    logic signed [PBIT_8EDGE_COMPUTE_WIDTH-1:0] c_nw_ext;

    pbit_edge_contrib2 u_contrib_n (
        .accept_i        (accept_n_i),
        .edge_sign_i     (edge_sign_n_i),
        .neighbor_spin_i (neighbor_spin_n_i),
        .contrib_o       (c_n)
    );

    pbit_edge_contrib2 u_contrib_ne (
        .accept_i        (accept_ne_i),
        .edge_sign_i     (edge_sign_ne_i),
        .neighbor_spin_i (neighbor_spin_ne_i),
        .contrib_o       (c_ne)
    );

    pbit_edge_contrib2 u_contrib_e (
        .accept_i        (accept_e_i),
        .edge_sign_i     (edge_sign_e_i),
        .neighbor_spin_i (neighbor_spin_e_i),
        .contrib_o       (c_e)
    );

    pbit_edge_contrib2 u_contrib_se (
        .accept_i        (accept_se_i),
        .edge_sign_i     (edge_sign_se_i),
        .neighbor_spin_i (neighbor_spin_se_i),
        .contrib_o       (c_se)
    );

    pbit_edge_contrib2 u_contrib_s (
        .accept_i        (accept_s_i),
        .edge_sign_i     (edge_sign_s_i),
        .neighbor_spin_i (neighbor_spin_s_i),
        .contrib_o       (c_s)
    );

    pbit_edge_contrib2 u_contrib_sw (
        .accept_i        (accept_sw_i),
        .edge_sign_i     (edge_sign_sw_i),
        .neighbor_spin_i (neighbor_spin_sw_i),
        .contrib_o       (c_sw)
    );

    pbit_edge_contrib2 u_contrib_w (
        .accept_i        (accept_w_i),
        .edge_sign_i     (edge_sign_w_i),
        .neighbor_spin_i (neighbor_spin_w_i),
        .contrib_o       (c_w)
    );

    pbit_edge_contrib2 u_contrib_nw (
        .accept_i        (accept_nw_i),
        .edge_sign_i     (edge_sign_nw_i),
        .neighbor_spin_i (neighbor_spin_nw_i),
        .contrib_o       (c_nw)
    );

    assign c_n_ext  = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_n[1]}},  c_n});
    assign c_ne_ext = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_ne[1]}}, c_ne});
    assign c_e_ext  = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_e[1]}},  c_e});
    assign c_se_ext = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_se[1]}}, c_se});
    assign c_s_ext  = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_s[1]}},  c_s});
    assign c_sw_ext = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_sw[1]}}, c_sw});
    assign c_w_ext  = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_w[1]}},  c_w});
    assign c_nw_ext = $signed({{(PBIT_8EDGE_COMPUTE_WIDTH-2){c_nw[1]}}, c_nw});

    assign h_sum_o =
        c_n_ext  +
        c_ne_ext +
        c_e_ext  +
        c_se_ext +
        c_s_ext  +
        c_sw_ext +
        c_w_ext  +
        c_nw_ext;

endmodule
`endif