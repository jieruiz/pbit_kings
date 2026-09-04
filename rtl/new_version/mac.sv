`ifndef MAC
`define MAC
import pbit_pkg::*;
module mac(
    input logic clk,

    input logic [3:0] mac_sel_i,
    // ------------------------------------------------------------
    // Shared 32_bit lfsr random int
    // ------------------------------------------------------------
    input logic [31:0] rnd32_i,
    
    // Neighbor spins color1
    // ------------------------------------------------------------
    input logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_0_i,
    input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_0_i,

    input logic neighbor_spin_n_0_i,
    input logic neighbor_spin_ne_0_i,
    input logic neighbor_spin_e_0_i,
    input logic neighbor_spin_se_0_i,
    input logic neighbor_spin_s_0_i,
    input logic neighbor_spin_sw_0_i,
    input logic neighbor_spin_w_0_i,
    input logic neighbor_spin_nw_0_i,

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_0_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_0_i,

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1, 1 means J=-1
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_0_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_0_i,

    // ------------------------------------------------------------
    // Edge probability, 4-bit
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_0_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_0_i,

    // Neighbor spins color1
    // ------------------------------------------------------------
    input logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_1_i,
    input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_1_i,

    input logic neighbor_spin_n_1_i,
    input logic neighbor_spin_ne_1_i,
    input logic neighbor_spin_e_1_i,
    input logic neighbor_spin_se_1_i,
    input logic neighbor_spin_s_1_i,
    input logic neighbor_spin_sw_1_i,
    input logic neighbor_spin_w_1_i,
    input logic neighbor_spin_nw_1_i,

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_1_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_1_i,

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1, 1 means J=-1
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_1_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_1_i,

    // ------------------------------------------------------------
    // Edge probability, 4-bit
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_1_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_1_i,

    // Neighbor spins color2
    // ------------------------------------------------------------
    input logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_2_i,
    input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_2_i,

    input logic neighbor_spin_n_2_i,
    input logic neighbor_spin_ne_2_i,
    input logic neighbor_spin_e_2_i,
    input logic neighbor_spin_se_2_i,
    input logic neighbor_spin_s_2_i,
    input logic neighbor_spin_sw_2_i,
    input logic neighbor_spin_w_2_i,
    input logic neighbor_spin_nw_2_i,

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_2_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_2_i,

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1, 1 means J=-1
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_2_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_2_i,

    // ------------------------------------------------------------
    // Edge probability, 4-bit
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_2_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_2_i,

    // Neighbor spins color3
    // ------------------------------------------------------------
    input logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_3_i,
    input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_3_i,

    input logic neighbor_spin_n_3_i,
    input logic neighbor_spin_ne_3_i,
    input logic neighbor_spin_e_3_i,
    input logic neighbor_spin_se_3_i,
    input logic neighbor_spin_s_3_i,
    input logic neighbor_spin_sw_3_i,
    input logic neighbor_spin_w_3_i,
    input logic neighbor_spin_nw_3_i,

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_3_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_3_i,

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1, 1 means J=-1
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_3_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_3_i,

    // ------------------------------------------------------------
    // Edge probability, 4-bit
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_3_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_3_i,

    // ------------------------------------------------------------
    // macsum port
    // ------------------------------------------------------------
    input  logic                               macsum_en_i,
    output logic signed [MACSUM_WIDTH-1:0]     macsum_o
);
    // ------------------------------------------------------------
    // bias contribution
    // ------------------------------------------------------------
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_sel_w;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_sel_w;

    // ------------------------------------------------------------
    // spin valid
    // ------------------------------------------------------------
    
    logic neighbor_spin_n_sel_w;
    logic neighbor_spin_ne_sel_w;
    logic neighbor_spin_e_sel_w;
    logic neighbor_spin_se_sel_w;
    logic neighbor_spin_s_sel_w;
    logic neighbor_spin_sw_sel_w;
    logic neighbor_spin_w_sel_w;
    logic neighbor_spin_nw_sel_w;

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_sel_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_sel_w;

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1; 1 means J=-1
    // ------------------------------------------------------------
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_sel_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_sel_w;

    // ------------------------------------------------------------
    // Edge probability; 4-bit
    // ------------------------------------------------------------
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_sel_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_sel_w;

    // ------------------------------------------------------------
    // 32-bit lfsr
    // ------------------------------------------------------------
    logic  [31:0] rnd32_w;

    // ------------------------------------------------------------
    // 8 edge probability compares
    // ------------------------------------------------------------
    logic accept_n_w;
    logic accept_ne_w;
    logic accept_e_w;
    logic accept_se_w;
    logic accept_s_w;
    logic accept_sw_w;
    logic accept_w_w;
    logic accept_nw_w;

    // ------------------------------------------------------------
    // bias probability compares
    // ------------------------------------------------------------
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_rand_w;
    logic accept_bias_w;

    // ------------------------------------------------------------
    // 8 edge contribution compute
    // ------------------------------------------------------------
    logic signed [MACSUM_WIDTH-1:0] h_sum_w;
    logic signed [MACSUM_WIDTH-4:0] bias_contrib_w;
    logic signed [MACSUM_WIDTH-1:0] bias_contrib_ext_w;
    logic signed [MACSUM_WIDTH-1:0] h_sum_with_bias_w;

    // ------------------------------------------------------------
    // macsum
    // ------------------------------------------------------------
    logic [MACSUM_WIDTH-1:0]        macsum_q_raw;
    logic signed [MACSUM_WIDTH-1:0] macsum_q, macsum_d;
    logic                           macsum_en;

    always @(*)begin
        case(mac_sel_i)
            4'b0001: begin
                bias_sign_sel_w = bias_sign_0_i;
                bias_prob_sel_w = bias_prob_0_i;

                neighbor_spin_n_sel_w  = neighbor_spin_n_0_i;
                neighbor_spin_ne_sel_w = neighbor_spin_ne_0_i;
                neighbor_spin_e_sel_w  = neighbor_spin_e_0_i;
                neighbor_spin_se_sel_w = neighbor_spin_se_0_i;
                neighbor_spin_s_sel_w  = neighbor_spin_s_0_i;
                neighbor_spin_sw_sel_w = neighbor_spin_sw_0_i;
                neighbor_spin_w_sel_w  = neighbor_spin_w_0_i;
                neighbor_spin_nw_sel_w = neighbor_spin_nw_0_i;

                edge_valid_n_sel_w  = edge_valid_n_0_i;
                edge_valid_ne_sel_w = edge_valid_ne_0_i;
                edge_valid_e_sel_w  = edge_valid_e_0_i;
                edge_valid_se_sel_w = edge_valid_se_0_i;
                edge_valid_s_sel_w  = edge_valid_s_0_i;
                edge_valid_sw_sel_w = edge_valid_sw_0_i;
                edge_valid_w_sel_w  = edge_valid_w_0_i;
                edge_valid_nw_sel_w = edge_valid_nw_0_i;

                edge_sign_n_sel_w  = edge_sign_n_0_i;
                edge_sign_ne_sel_w = edge_sign_ne_0_i;
                edge_sign_e_sel_w  = edge_sign_e_0_i;
                edge_sign_se_sel_w = edge_sign_se_0_i;
                edge_sign_s_sel_w  = edge_sign_s_0_i;
                edge_sign_sw_sel_w = edge_sign_sw_0_i;
                edge_sign_w_sel_w  = edge_sign_w_0_i;
                edge_sign_nw_sel_w = edge_sign_nw_0_i;

                edge_prob_n_sel_w  = edge_prob_n_0_i;
                edge_prob_ne_sel_w = edge_prob_ne_0_i;
                edge_prob_e_sel_w  = edge_prob_e_0_i;
                edge_prob_se_sel_w = edge_prob_se_0_i;
                edge_prob_s_sel_w  = edge_prob_s_0_i;
                edge_prob_sw_sel_w = edge_prob_sw_0_i;
                edge_prob_w_sel_w  = edge_prob_w_0_i;
                edge_prob_nw_sel_w = edge_prob_nw_0_i;
            end
            4'b0010: begin
                bias_sign_sel_w = bias_sign_1_i;
                bias_prob_sel_w = bias_prob_1_i;

                neighbor_spin_n_sel_w  = neighbor_spin_n_1_i;
                neighbor_spin_ne_sel_w = neighbor_spin_ne_1_i;
                neighbor_spin_e_sel_w  = neighbor_spin_e_1_i;
                neighbor_spin_se_sel_w = neighbor_spin_se_1_i;
                neighbor_spin_s_sel_w  = neighbor_spin_s_1_i;
                neighbor_spin_sw_sel_w = neighbor_spin_sw_1_i;
                neighbor_spin_w_sel_w  = neighbor_spin_w_1_i;
                neighbor_spin_nw_sel_w = neighbor_spin_nw_1_i;

                edge_valid_n_sel_w  = edge_valid_n_1_i;
                edge_valid_ne_sel_w = edge_valid_ne_1_i;
                edge_valid_e_sel_w  = edge_valid_e_1_i;
                edge_valid_se_sel_w = edge_valid_se_1_i;
                edge_valid_s_sel_w  = edge_valid_s_1_i;
                edge_valid_sw_sel_w = edge_valid_sw_1_i;
                edge_valid_w_sel_w  = edge_valid_w_1_i;
                edge_valid_nw_sel_w = edge_valid_nw_1_i;

                edge_sign_n_sel_w  = edge_sign_n_1_i;
                edge_sign_ne_sel_w = edge_sign_ne_1_i;
                edge_sign_e_sel_w  = edge_sign_e_1_i;
                edge_sign_se_sel_w = edge_sign_se_1_i;
                edge_sign_s_sel_w  = edge_sign_s_1_i;
                edge_sign_sw_sel_w = edge_sign_sw_1_i;
                edge_sign_w_sel_w  = edge_sign_w_1_i;
                edge_sign_nw_sel_w = edge_sign_nw_1_i;

                edge_prob_n_sel_w  = edge_prob_n_1_i;
                edge_prob_ne_sel_w = edge_prob_ne_1_i;
                edge_prob_e_sel_w  = edge_prob_e_1_i;
                edge_prob_se_sel_w = edge_prob_se_1_i;
                edge_prob_s_sel_w  = edge_prob_s_1_i;
                edge_prob_sw_sel_w = edge_prob_sw_1_i;
                edge_prob_w_sel_w  = edge_prob_w_1_i;
                edge_prob_nw_sel_w = edge_prob_nw_1_i;
            end
            4'b0100: begin
                bias_sign_sel_w = bias_sign_2_i;
                bias_prob_sel_w = bias_prob_2_i;

                neighbor_spin_n_sel_w  = neighbor_spin_n_2_i;
                neighbor_spin_ne_sel_w = neighbor_spin_ne_2_i;
                neighbor_spin_e_sel_w  = neighbor_spin_e_2_i;
                neighbor_spin_se_sel_w = neighbor_spin_se_2_i;
                neighbor_spin_s_sel_w  = neighbor_spin_s_2_i;
                neighbor_spin_sw_sel_w = neighbor_spin_sw_2_i;
                neighbor_spin_w_sel_w  = neighbor_spin_w_2_i;
                neighbor_spin_nw_sel_w = neighbor_spin_nw_2_i;

                edge_valid_n_sel_w  = edge_valid_n_2_i;
                edge_valid_ne_sel_w = edge_valid_ne_2_i;
                edge_valid_e_sel_w  = edge_valid_e_2_i;
                edge_valid_se_sel_w = edge_valid_se_2_i;
                edge_valid_s_sel_w  = edge_valid_s_2_i;
                edge_valid_sw_sel_w = edge_valid_sw_2_i;
                edge_valid_w_sel_w  = edge_valid_w_2_i;
                edge_valid_nw_sel_w = edge_valid_nw_2_i;

                edge_sign_n_sel_w  = edge_sign_n_2_i;
                edge_sign_ne_sel_w = edge_sign_ne_2_i;
                edge_sign_e_sel_w  = edge_sign_e_2_i;
                edge_sign_se_sel_w = edge_sign_se_2_i;
                edge_sign_s_sel_w  = edge_sign_s_2_i;
                edge_sign_sw_sel_w = edge_sign_sw_2_i;
                edge_sign_w_sel_w  = edge_sign_w_2_i;
                edge_sign_nw_sel_w = edge_sign_nw_2_i;

                edge_prob_n_sel_w  = edge_prob_n_2_i;
                edge_prob_ne_sel_w = edge_prob_ne_2_i;
                edge_prob_e_sel_w  = edge_prob_e_2_i;
                edge_prob_se_sel_w = edge_prob_se_2_i;
                edge_prob_s_sel_w  = edge_prob_s_2_i;
                edge_prob_sw_sel_w = edge_prob_sw_2_i;
                edge_prob_w_sel_w  = edge_prob_w_2_i;
                edge_prob_nw_sel_w = edge_prob_nw_2_i;
            end
            4'b1000: begin
                bias_sign_sel_w = bias_sign_3_i;
                bias_prob_sel_w = bias_prob_3_i;

                neighbor_spin_n_sel_w  = neighbor_spin_n_3_i;
                neighbor_spin_ne_sel_w = neighbor_spin_ne_3_i;
                neighbor_spin_e_sel_w  = neighbor_spin_e_3_i;
                neighbor_spin_se_sel_w = neighbor_spin_se_3_i;
                neighbor_spin_s_sel_w  = neighbor_spin_s_3_i;
                neighbor_spin_sw_sel_w = neighbor_spin_sw_3_i;
                neighbor_spin_w_sel_w  = neighbor_spin_w_3_i;
                neighbor_spin_nw_sel_w = neighbor_spin_nw_3_i;

                edge_valid_n_sel_w  = edge_valid_n_3_i;
                edge_valid_ne_sel_w = edge_valid_ne_3_i;
                edge_valid_e_sel_w  = edge_valid_e_3_i;
                edge_valid_se_sel_w = edge_valid_se_3_i;
                edge_valid_s_sel_w  = edge_valid_s_3_i;
                edge_valid_sw_sel_w = edge_valid_sw_3_i;
                edge_valid_w_sel_w  = edge_valid_w_3_i;
                edge_valid_nw_sel_w = edge_valid_nw_3_i;

                edge_sign_n_sel_w  = edge_sign_n_3_i;
                edge_sign_ne_sel_w = edge_sign_ne_3_i;
                edge_sign_e_sel_w  = edge_sign_e_3_i;
                edge_sign_se_sel_w = edge_sign_se_3_i;
                edge_sign_s_sel_w  = edge_sign_s_3_i;
                edge_sign_sw_sel_w = edge_sign_sw_3_i;
                edge_sign_w_sel_w  = edge_sign_w_3_i;
                edge_sign_nw_sel_w = edge_sign_nw_3_i;

                edge_prob_n_sel_w  = edge_prob_n_3_i;
                edge_prob_ne_sel_w = edge_prob_ne_3_i;
                edge_prob_e_sel_w  = edge_prob_e_3_i;
                edge_prob_se_sel_w = edge_prob_se_3_i;
                edge_prob_s_sel_w  = edge_prob_s_3_i;
                edge_prob_sw_sel_w = edge_prob_sw_3_i;
                edge_prob_w_sel_w  = edge_prob_w_3_i;
                edge_prob_nw_sel_w = edge_prob_nw_3_i;
            end
            default: begin
                bias_sign_sel_w = bias_sign_0_i;
                bias_prob_sel_w = bias_prob_0_i;

                neighbor_spin_n_sel_w  = neighbor_spin_n_0_i;
                neighbor_spin_ne_sel_w = neighbor_spin_ne_0_i;
                neighbor_spin_e_sel_w  = neighbor_spin_e_0_i;
                neighbor_spin_se_sel_w = neighbor_spin_se_0_i;
                neighbor_spin_s_sel_w  = neighbor_spin_s_0_i;
                neighbor_spin_sw_sel_w = neighbor_spin_sw_0_i;
                neighbor_spin_w_sel_w  = neighbor_spin_w_0_i;
                neighbor_spin_nw_sel_w = neighbor_spin_nw_0_i;

                edge_valid_n_sel_w  = edge_valid_n_0_i;
                edge_valid_ne_sel_w = edge_valid_ne_0_i;
                edge_valid_e_sel_w  = edge_valid_e_0_i;
                edge_valid_se_sel_w = edge_valid_se_0_i;
                edge_valid_s_sel_w  = edge_valid_s_0_i;
                edge_valid_sw_sel_w = edge_valid_sw_0_i;
                edge_valid_w_sel_w  = edge_valid_w_0_i;
                edge_valid_nw_sel_w = edge_valid_nw_0_i;

                edge_sign_n_sel_w  = edge_sign_n_0_i;
                edge_sign_ne_sel_w = edge_sign_ne_0_i;
                edge_sign_e_sel_w  = edge_sign_e_0_i;
                edge_sign_se_sel_w = edge_sign_se_0_i;
                edge_sign_s_sel_w  = edge_sign_s_0_i;
                edge_sign_sw_sel_w = edge_sign_sw_0_i;
                edge_sign_w_sel_w  = edge_sign_w_0_i;
                edge_sign_nw_sel_w = edge_sign_nw_0_i;

                edge_prob_n_sel_w  = edge_prob_n_0_i;
                edge_prob_ne_sel_w = edge_prob_ne_0_i;
                edge_prob_e_sel_w  = edge_prob_e_0_i;
                edge_prob_se_sel_w = edge_prob_se_0_i;
                edge_prob_s_sel_w  = edge_prob_s_0_i;
                edge_prob_sw_sel_w = edge_prob_sw_0_i;
                edge_prob_w_sel_w  = edge_prob_w_0_i;
                edge_prob_nw_sel_w = edge_prob_nw_0_i;
            end
        endcase
    end

    // ------------------------------------------------------------
    // 32-bit lfsr
    // ------------------------------------------------------------
    assign rnd32_w = rnd32_i;

    // ------------------------------------------------------------
    // 8 edge probability compares
    // ------------------------------------------------------------
    edge_compare8_named u_edge_compare8_named (
        .edge_rand32_i  (rnd32_w),

        .edge_prob_n_i  (edge_prob_n_sel_w),
        .edge_prob_ne_i (edge_prob_ne_sel_w),
        .edge_prob_e_i  (edge_prob_e_sel_w),
        .edge_prob_se_i (edge_prob_se_sel_w),
        .edge_prob_s_i  (edge_prob_s_sel_w),
        .edge_prob_sw_i (edge_prob_sw_sel_w),
        .edge_prob_w_i  (edge_prob_w_sel_w),
        .edge_prob_nw_i (edge_prob_nw_sel_w),

        .edge_valid_n_i  (edge_valid_n_sel_w),
        .edge_valid_ne_i (edge_valid_ne_sel_w),
        .edge_valid_e_i  (edge_valid_e_sel_w),
        .edge_valid_se_i (edge_valid_se_sel_w),
        .edge_valid_s_i  (edge_valid_s_sel_w),
        .edge_valid_sw_i (edge_valid_sw_sel_w),
        .edge_valid_w_i  (edge_valid_w_sel_w),
        .edge_valid_nw_i (edge_valid_nw_sel_w),

        .accept_n_o  (accept_n_w),
        .accept_ne_o (accept_ne_w),
        .accept_e_o  (accept_e_w),
        .accept_se_o (accept_se_w),
        .accept_s_o  (accept_s_w),
        .accept_sw_o (accept_sw_w),
        .accept_w_o  (accept_w_w),
        .accept_nw_o (accept_nw_w)
    );

    // ------------------------------------------------------------
    // bias probability compares
    // ------------------------------------------------------------
    assign bias_rand_w = {
        rnd32_w[12],
        rnd32_w[10],        
        rnd32_w[8],
        rnd32_w[6],
        rnd32_w[4],
        rnd32_w[2],
        rnd32_w[0]
    };
    edge_prob_compare #(
        .WIDTH(NODE_CFG_BIAS_PROB_WIDTH)    
    ) u_bias_prob_compare (
        .rand_i   (bias_rand_w),
        .prob_i   (bias_prob_sel_w),
        .valid_i  (1'b1),
        .accept_o (accept_bias_w)
    );

    // ------------------------------------------------------------
    // 8 edge contribution compute
    // ------------------------------------------------------------
    pbit_8edge_compute u_pbit_8edge_compute (
        .accept_n_i  (accept_n_w),
        .accept_ne_i (accept_ne_w),
        .accept_e_i  (accept_e_w),
        .accept_se_i (accept_se_w),
        .accept_s_i  (accept_s_w),
        .accept_sw_i (accept_sw_w),
        .accept_w_i  (accept_w_w),
        .accept_nw_i (accept_nw_w),

        .edge_sign_n_i  (edge_sign_n_sel_w),
        .edge_sign_ne_i (edge_sign_ne_sel_w),
        .edge_sign_e_i  (edge_sign_e_sel_w),
        .edge_sign_se_i (edge_sign_se_sel_w),
        .edge_sign_s_i  (edge_sign_s_sel_w),
        .edge_sign_sw_i (edge_sign_sw_sel_w),
        .edge_sign_w_i  (edge_sign_w_sel_w),
        .edge_sign_nw_i (edge_sign_nw_sel_w),

        .neighbor_spin_n_i  (neighbor_spin_n_sel_w),
        .neighbor_spin_ne_i (neighbor_spin_ne_sel_w),
        .neighbor_spin_e_i  (neighbor_spin_e_sel_w),
        .neighbor_spin_se_i (neighbor_spin_se_sel_w),
        .neighbor_spin_s_i  (neighbor_spin_s_sel_w),
        .neighbor_spin_sw_i (neighbor_spin_sw_sel_w),
        .neighbor_spin_w_i  (neighbor_spin_w_sel_w),
        .neighbor_spin_nw_i (neighbor_spin_nw_sel_w),

        .h_sum_o (h_sum_w)
    );

    pbit_edge_contrib2 u_bias_contrib (
        .accept_i        (accept_bias_w),
        .edge_sign_i     (bias_sign_sel_w),
        .neighbor_spin_i (1'b1),
        .contrib_o       (bias_contrib_w)
    );

    assign bias_contrib_ext_w = $signed({{3{bias_contrib_w[1]}}, bias_contrib_w});
    assign h_sum_with_bias_w  = h_sum_w + bias_contrib_ext_w;

    assign macsum_d  = h_sum_with_bias_w;
    assign macsum_en = macsum_en_i;
    assign macsum_o  = macsum_q;
    assign macsum_q  = $signed(macsum_q_raw);

    dffe #(.WIDTH(5)
    ) macsum_ff (
        .clk(clk),
        .en_i(macsum_en),
        .d_i($unsigned(macsum_d)),
        .q_o(macsum_q_raw)
    ); 
endmodule
`endif