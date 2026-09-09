`ifndef PBIT_TOP
`define PBIT_TOP
import pbit_pkg::*;
module pbit_top (
    input  logic clk,
    input  logic rst_n,
    input  logic uart_rx_i,
    output logic uart_tx_o
);
    logic uart_rx_busy_w, uart_tx_busy_w;
    logic run_busy_w, run_done_w;
    logic [SNAPSHOT_WIDTH-1:0] snapshot_flat_w;
    logic snapshot_vld_w;
    logic [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr_w;
    logic snapshot_latch_pulse_w, snapshot_valid_clr_w;
    logic [I0_LEVEL_WIDTH-1:0] i0_level_arr_w [SWEEP_ROUND_NUM];
    logic [I0_LEVEL_WIDTH-1:0] i0_level_w;
    logic [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_w [SWEEP_ROUND_NUM];
    logic cfg_done_w, run_start_pulse_w, run_done_clr_pulse_w;
    logic [NUM_SWEEP_WIDTH-1:0] num_sweeps_w;
    logic [NUM_MAJORITY_WIDTH-1:0] num_majority_w;
    logic cfg_req_valid_w, cfg_req_ready_w, cfg_rsp_valid_w;
    cfg_array_req_t cfg_req_w;
    cfg_rsp_t cfg_rsp_w;
    logic phase_start_w, phase_w, all_phase_done_w;

    // reg_block owns request legality, CFG_BUSY and completion status.
    pbit_uart_reg_subsystem u_uart_reg_subsystem (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .uart_rx_i                 (uart_rx_i),
        .uart_tx_o                 (uart_tx_o),
        .uart_rx_busy_o            (uart_rx_busy_w),
        .uart_tx_busy_o            (uart_tx_busy_w),
        .run_busy_i                (run_busy_w),
        .run_done_i                (run_done_w),
        .snapshot_flat_i           (snapshot_flat_w),
        .snapshot_vld_i            (snapshot_vld_w),
        .snapshot_addr_o           (snapshot_addr_w),
        .snapshot_latch_pulse_o    (snapshot_latch_pulse_w),
        .snapshot_valid_clr_o      (snapshot_valid_clr_w),
        .i0_level_o                (i0_level_arr_w),
        .sweep_interval_o          (sweep_interval_w),
        .cfg_done_o                (cfg_done_w),
        .run_start_pulse_o         (run_start_pulse_w),
        .run_done_clr_pulse_o      (run_done_clr_pulse_w),
        .num_sweeps_o              (num_sweeps_w),
        .num_majority_o            (num_majority_w),
        .cfg_req_valid_o           (cfg_req_valid_w),
        .cfg_req_ready_i           (cfg_req_ready_w),
        .cfg_req_o                 (cfg_req_w),
        .cfg_rsp_valid_i           (cfg_rsp_valid_w),
        .cfg_rsp_i                 (cfg_rsp_w)
    );

    // Registered phase start lets BANKs capture the updated phase and I0.
    phase_control u_phase_control (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .cfg_done_i                (cfg_done_w),
        .run_start_pulse_i         (run_start_pulse_w),
        .run_done_clr_pulse_i      (run_done_clr_pulse_w),
        .num_sweeps_i              (num_sweeps_w),
        .i0_level_i                (i0_level_arr_w),
        .sweep_interval_i          (sweep_interval_w),
        .all_phase_done_i          (all_phase_done_w),
        .phase_start_o             (phase_start_w),
        .phase_o                   (phase_w),
        .i0_level_o                (i0_level_w),
        .run_busy_o                (run_busy_w),
        .run_done_o                (run_done_w)
    );

    // The array routes configuration and returns representative BANK completion.
    pbit_array_chimera u_pbit_array_chimera (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .cfg_req_valid_i           (cfg_req_valid_w),
        .cfg_req_ready_o           (cfg_req_ready_w),
        .cfg_req_i                 (cfg_req_w),
        .cfg_rsp_valid_o           (cfg_rsp_valid_w),
        .cfg_rsp_o                 (cfg_rsp_w),
        .phase_start_i             (phase_start_w),
        .phase_i                   (phase_w),
        .i0_level_i                (i0_level_w),
        .num_majority_i            (num_majority_w),
        .all_phase_done_o          (all_phase_done_w),
        .snapshot_addr_i           (snapshot_addr_w),
        .snapshot_latch_pulse_i    (snapshot_latch_pulse_w),
        .snapshot_valid_clr_i      (snapshot_valid_clr_w),
        .snapshot_flat_o           (snapshot_flat_w),
        .snapshot_vld_o            (snapshot_vld_w)
    );

endmodule
`endif
