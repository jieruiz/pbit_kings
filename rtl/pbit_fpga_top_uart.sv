`timescale 1ns / 1ps

module pbit_fpga_top_uart_run #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer ROWS        = 19,
    parameter integer COLS        = 19,
    parameter integer N_TRIAL     = 5,
    parameter integer NUM_SWEEPS  = 50
)(
    input  wire clk,
    input  wire rst_n,

    input  wire uart_rx_i,
    output wire uart_tx_o,

    output wire cfg_done_o,
    output wire run_busy_o,
    output wire run_done_o,
    output wire [31:0] sweep_cnt_o,

    output wire [ROWS*COLS-1:0] spin_flat_o
);

    localparam integer N_SPIN = ROWS * COLS;

    wire        cfg_node_we_w;
    wire [4:0]  cfg_node_row_w;
    wire [4:0]  cfg_node_col_w;
    wire [31:0] cfg_node_seed_w;
    wire        cfg_node_init_spin_w;
    wire        cfg_node_clamp_en_w;
    wire        cfg_node_clamp_spin_w;
    wire        cfg_node_bias_sign_w;
    wire [3:0]  cfg_node_bias_prob4_w;

    wire        cfg_edge_we_w;
    wire [1:0]  cfg_edge_type_w;
    wire [4:0]  cfg_edge_row_w;
    wire [4:0]  cfg_edge_col_w;
    wire [3:0]  cfg_edge_prob4_w;
    wire        cfg_edge_sign_w;
    wire        cfg_edge_valid_w;

    wire run_start_pulse_w;

    wire phase_start_c0_w;
    wire phase_start_c1_w;
    wire phase_start_c2_w;
    wire phase_start_c3_w;

    wire all_done_c0_w;
    wire all_done_c1_w;
    wire all_done_c2_w;
    wire all_done_c3_w;

    wire [3:0] i0_level_w;
    wire sweep_done_pulse_w;

    wire [31:0] cmd_count_w;

    pbit_uart_host_if #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .N_SPIN     (N_SPIN)
    ) u_pbit_uart_host_if (
        .clk       (clk),
        .rst_n     (rst_n),

        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o),

        .spin_flat_i (spin_flat_o),

        .cfg_node_we_o         (cfg_node_we_w),
        .cfg_node_row_o        (cfg_node_row_w),
        .cfg_node_col_o        (cfg_node_col_w),
        .cfg_node_seed_o       (cfg_node_seed_w),
        .cfg_node_init_spin_o  (cfg_node_init_spin_w),
        .cfg_node_clamp_en_o   (cfg_node_clamp_en_w),
        .cfg_node_clamp_spin_o (cfg_node_clamp_spin_w),
        .cfg_node_bias_sign_o  (cfg_node_bias_sign_w),
        .cfg_node_bias_prob4_o (cfg_node_bias_prob4_w),

        .cfg_edge_we_o     (cfg_edge_we_w),
        .cfg_edge_type_o   (cfg_edge_type_w),
        .cfg_edge_row_o    (cfg_edge_row_w),
        .cfg_edge_col_o    (cfg_edge_col_w),
        .cfg_edge_prob4_o  (cfg_edge_prob4_w),
        .cfg_edge_sign_o   (cfg_edge_sign_w),
        .cfg_edge_valid_o  (cfg_edge_valid_w),

        .cfg_done_o        (cfg_done_o),
        .run_start_pulse_o (run_start_pulse_w),

        .cmd_count_o       (cmd_count_w)
    );

    pbit_array_kings #(
        .ROWS(ROWS),
        .COLS(COLS),
        .N_TRIAL(N_TRIAL)
    ) u_pbit_array_kings (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .phase_start_c0_i       (phase_start_c0_w),
        .phase_start_c1_i       (phase_start_c1_w),
        .phase_start_c2_i       (phase_start_c2_w),
        .phase_start_c3_i       (phase_start_c3_w),

        .i0_level_i             (i0_level_w),

        .cfg_node_we_i          (cfg_node_we_w),
        .cfg_node_row_i         (cfg_node_row_w),
        .cfg_node_col_i         (cfg_node_col_w),
        .cfg_node_seed_i        (cfg_node_seed_w),
        .cfg_node_init_spin_i   (cfg_node_init_spin_w),
        .cfg_node_clamp_en_i    (cfg_node_clamp_en_w),
        .cfg_node_clamp_spin_i  (cfg_node_clamp_spin_w),
        .cfg_node_bias_sign_i   (cfg_node_bias_sign_w),
        .cfg_node_bias_prob4_i  (cfg_node_bias_prob4_w),

        .cfg_edge_we_i          (cfg_edge_we_w),
        .cfg_edge_type_i        (cfg_edge_type_w),
        .cfg_edge_row_i         (cfg_edge_row_w),
        .cfg_edge_col_i         (cfg_edge_col_w),
        .cfg_edge_prob4_i       (cfg_edge_prob4_w),
        .cfg_edge_sign_i        (cfg_edge_sign_w),
        .cfg_edge_valid_i       (cfg_edge_valid_w),

        .all_done_c0_o          (all_done_c0_w),
        .all_done_c1_o          (all_done_c1_w),
        .all_done_c2_o          (all_done_c2_w),
        .all_done_c3_o          (all_done_c3_w),

        .spin_flat_o            (spin_flat_o)
    );

    phase_ctrl_4color #(
        .NUM_SWEEPS(NUM_SWEEPS)
    ) u_phase_ctrl_4color (
        .clk               (clk),
        .rst_n             (rst_n),

        .cfg_done_i        (cfg_done_o),
        .run_start_pulse_i (run_start_pulse_w),

        .all_done_c0_i     (all_done_c0_w),
        .all_done_c1_i     (all_done_c1_w),
        .all_done_c2_i     (all_done_c2_w),
        .all_done_c3_i     (all_done_c3_w),

        .phase_start_c0_o  (phase_start_c0_w),
        .phase_start_c1_o  (phase_start_c1_w),
        .phase_start_c2_o  (phase_start_c2_w),
        .phase_start_c3_o  (phase_start_c3_w),

        .i0_level_o        (i0_level_w),
        .sweep_cnt_o       (sweep_cnt_o),

        .sweep_done_pulse_o(sweep_done_pulse_w),
        .run_busy_o        (run_busy_o),
        .run_done_o        (run_done_o)
    );

endmodule
