`timescale 1ns / 1ps

module pbit_node #(
    parameter integer N_TRIAL = 5
)(
    input  wire clk,
    input  wire rst_n,

    // ------------------------------------------------------------
    // Local phase start.
    // This is already color-decoded by array-level wiring.
    // ------------------------------------------------------------
    input  wire       local_start_i,
    input  wire [3:0] i0_level_i,

    // ------------------------------------------------------------
    // Node configuration interface.
    // Used during CONFIG phase.
    // ------------------------------------------------------------
    input  wire        cfg_node_we_i,
    input  wire [31:0] cfg_seed_i,
    input  wire        cfg_init_spin_i,
    input  wire        cfg_clamp_en_i,
    input  wire        cfg_clamp_spin_i,
    input  wire        cfg_bias_sign_i,
    input  wire [3:0]  cfg_bias_prob4_i,

    // ------------------------------------------------------------
    // Neighbor spins
    // ------------------------------------------------------------
    input wire neighbor_spin_n_i,
    input wire neighbor_spin_ne_i,
    input wire neighbor_spin_e_i,
    input wire neighbor_spin_se_i,
    input wire neighbor_spin_s_i,
    input wire neighbor_spin_sw_i,
    input wire neighbor_spin_w_i,
    input wire neighbor_spin_nw_i,

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    input wire edge_valid_n_i,
    input wire edge_valid_ne_i,
    input wire edge_valid_e_i,
    input wire edge_valid_se_i,
    input wire edge_valid_s_i,
    input wire edge_valid_sw_i,
    input wire edge_valid_w_i,
    input wire edge_valid_nw_i,

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1, 0 means J=-1
    // ------------------------------------------------------------
    input wire edge_sign_n_i,
    input wire edge_sign_ne_i,
    input wire edge_sign_e_i,
    input wire edge_sign_se_i,
    input wire edge_sign_s_i,
    input wire edge_sign_sw_i,
    input wire edge_sign_w_i,
    input wire edge_sign_nw_i,

    // ------------------------------------------------------------
    // Edge probability, 4-bit
    // ------------------------------------------------------------
    input wire [3:0] edge_prob_n_i,
    input wire [3:0] edge_prob_ne_i,
    input wire [3:0] edge_prob_e_i,
    input wire [3:0] edge_prob_se_i,
    input wire [3:0] edge_prob_s_i,
    input wire [3:0] edge_prob_sw_i,
    input wire [3:0] edge_prob_w_i,
    input wire [3:0] edge_prob_nw_i,

    // ------------------------------------------------------------
    // Runtime outputs
    // ------------------------------------------------------------
    output wire       spin_o,
    output wire       busy_o,
    output wire       done_pulse_o,
    output reg        done_hold_o,
    output wire       flip_o
);

    reg clamp_en_q;
    reg clamp_spin_q;
    reg bias_sign_q;
    reg [3:0] bias_prob4_q;

    // ------------------------------------------------------------
    // Clamp registers.
    // Seed and initial spin are loaded directly into update core.
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clamp_en_q   <= 1'b0;
            clamp_spin_q <= 1'b0;
            bias_sign_q  <= 1'b1;
            bias_prob4_q <= 4'd0;
        end else if (cfg_node_we_i) begin
            clamp_en_q   <= cfg_clamp_en_i;
            clamp_spin_q <= cfg_clamp_spin_i;
            bias_sign_q  <= cfg_bias_sign_i;
            bias_prob4_q <= cfg_bias_prob4_i;
        end
    end

    // During cfg write, temporarily disable clamp path so init_spin can load.
    wire core_clamp_en_w;
    assign core_clamp_en_w = cfg_node_we_i ? 1'b0 : clamp_en_q;

    pbit_update_core_named #(
        .N_TRIAL(N_TRIAL)
    ) u_pbit_update_core_named (
        .clk                 (clk),
        .rst_n               (rst_n),

        .load_seed_i         (cfg_node_we_i),
        .seed_i              (cfg_seed_i),

        .init_spin_we_i      (cfg_node_we_i),
        .init_spin_i         (cfg_init_spin_i),

        .clamp_en_i          (core_clamp_en_w),
        .clamp_spin_i        (clamp_spin_q),
        .bias_sign_i         (bias_sign_q),
        .bias_prob4_i        (bias_prob4_q),

        .start_i             (local_start_i),
        .i0_level_i          (i0_level_i),

        .neighbor_spin_n_i   (neighbor_spin_n_i),
        .neighbor_spin_ne_i  (neighbor_spin_ne_i),
        .neighbor_spin_e_i   (neighbor_spin_e_i),
        .neighbor_spin_se_i  (neighbor_spin_se_i),
        .neighbor_spin_s_i   (neighbor_spin_s_i),
        .neighbor_spin_sw_i  (neighbor_spin_sw_i),
        .neighbor_spin_w_i   (neighbor_spin_w_i),
        .neighbor_spin_nw_i  (neighbor_spin_nw_i),

        .edge_valid_n_i      (edge_valid_n_i),
        .edge_valid_ne_i     (edge_valid_ne_i),
        .edge_valid_e_i      (edge_valid_e_i),
        .edge_valid_se_i     (edge_valid_se_i),
        .edge_valid_s_i      (edge_valid_s_i),
        .edge_valid_sw_i     (edge_valid_sw_i),
        .edge_valid_w_i      (edge_valid_w_i),
        .edge_valid_nw_i     (edge_valid_nw_i),

        .edge_sign_n_i       (edge_sign_n_i),
        .edge_sign_ne_i      (edge_sign_ne_i),
        .edge_sign_e_i       (edge_sign_e_i),
        .edge_sign_se_i      (edge_sign_se_i),
        .edge_sign_s_i       (edge_sign_s_i),
        .edge_sign_sw_i      (edge_sign_sw_i),
        .edge_sign_w_i       (edge_sign_w_i),
        .edge_sign_nw_i      (edge_sign_nw_i),

        .edge_prob_n_i       (edge_prob_n_i),
        .edge_prob_ne_i      (edge_prob_ne_i),
        .edge_prob_e_i       (edge_prob_e_i),
        .edge_prob_se_i      (edge_prob_se_i),
        .edge_prob_s_i       (edge_prob_s_i),
        .edge_prob_sw_i      (edge_prob_sw_i),
        .edge_prob_w_i       (edge_prob_w_i),
        .edge_prob_nw_i      (edge_prob_nw_i),

        .spin_o              (spin_o),
        .busy_o              (busy_o),
        .done_o              (done_pulse_o),
        .flip_o              (flip_o),

        .dbg_h_i_o           (),
        .dbg_plus_count_o    (),
        .dbg_edge_rand32_o   (),
        .dbg_pbit_rand16_o   (),
        .dbg_edge_accept_o   ()
    );

    // ------------------------------------------------------------
    // Hold done until the next local_start_i clears it.
    // Used by array-level phase controller.
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_hold_o <= 1'b0;
        end else begin
            if (local_start_i) begin
                done_hold_o <= 1'b0;
            end else if (done_pulse_o) begin
                done_hold_o <= 1'b1;
            end
        end
    end

endmodule
