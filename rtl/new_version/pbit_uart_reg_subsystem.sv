`ifndef PBIT_UART_REG_SUBSYSTEM
`define PBIT_UART_REG_SUBSYSTEM
import pbit_pkg::*;
// UART register access and Chimera array configuration bridge.
// Register accesses complete in one cycle; array commands complete via DONE.
module pbit_uart_reg_subsystem (
    input  logic clk,
    input  logic rst_n,

    // UART IO
    input  logic uart_rx_i,
    output logic uart_tx_o,
    output logic uart_rx_busy_o,
    output logic uart_tx_busy_o,

    // Runtime status from phase_control
    input  logic run_busy_i,
    input  logic run_done_i,

    // Snapshot IO
    input  logic [SNAPSHOT_WIDTH-1:0] snapshot_flat_i,
    input  logic snapshot_vld_i,
    output logic [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr_o,
    output logic snapshot_latch_pulse_o,
    output logic snapshot_valid_clr_o,

    // Annealing schedule and global control
    output logic [I0_LEVEL_WIDTH-1:0] i0_level_o [SWEEP_ROUND_NUM],
    output logic [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_o [SWEEP_ROUND_NUM],
    output logic cfg_done_o,
    output logic run_start_pulse_o,
    output logic run_done_clr_pulse_o,
    output logic [NUM_SWEEP_WIDTH-1:0] num_sweeps_o,
    output logic [NUM_MAJORITY_WIDTH-1:0] num_majority_o,

    // Unified NODE / SEED / EDGE configuration channel to the array.
    // reg_block checks legality and enforces one outstanding request via CFG_BUSY.
    // Request valid/data remain stable until ready; responses are always accepted.
    output logic cfg_req_valid_o,
    input  logic cfg_req_ready_i,
    output cfg_array_req_t cfg_req_o,
    input  logic cfg_rsp_valid_i,
    input  var cfg_rsp_t cfg_rsp_i
);
    logic        reg_wr_en_w;
    logic        reg_rd_en_w;
    logic [15:0] reg_addr_w;
    logic [31:0] reg_wdata_w;
    logic [31:0] reg_rdata_w;
    logic        reg_access_error_w;

    logic        uart_frame_err_pulse_w;
    logic        uart_overflow_pulse_w;

    pbit_uart_reg_master u_pbit_uart_reg_master (
        .clk                      (clk),
        .rst_n                    (rst_n),
      
        .uart_rx_i                (uart_rx_i),
        .uart_tx_o                (uart_tx_o),
      
        .reg_wr_en_o              (reg_wr_en_w),
        .reg_rd_en_o              (reg_rd_en_w),
        .reg_addr_o               (reg_addr_w),
        .reg_wdata_o              (reg_wdata_w),
        .reg_rdata_i              (reg_rdata_w),
        .reg_access_error_i       (reg_access_error_w),

        .uart_frame_err_pulse_o   (uart_frame_err_pulse_w),
        .uart_overflow_pulse_o    (uart_overflow_pulse_w),

        .uart_rx_busy_o           (uart_rx_busy_o),
        .uart_tx_busy_o           (uart_tx_busy_o)
    );

    pbit_reg_block u_pbit_reg_block (
        .clk                          (clk),
        .rst_n                        (rst_n),
        .reg_wr_en_i                  (reg_wr_en_w),
        .reg_rd_en_i                  (reg_rd_en_w),
        .reg_addr_i                   (reg_addr_w),
        .reg_wdata_i                  (reg_wdata_w),
        .reg_rdata_o                  (reg_rdata_w),
        .reg_access_error_o           (reg_access_error_w),
        .run_busy_i                   (run_busy_i),
        .run_done_i                   (run_done_i),
        .uart_frame_err_pulse_i       (uart_frame_err_pulse_w),
        .uart_overflow_pulse_i        (uart_overflow_pulse_w),
        .snapshot_flat_i              (snapshot_flat_i),
        .snapshot_vld_i               (snapshot_vld_i),
        .snapshot_addr_o              (snapshot_addr_o),
        .snapshot_latch_pulse_o       (snapshot_latch_pulse_o),
        .snapshot_valid_clr_o         (snapshot_valid_clr_o),
        .i0_level_o                   (i0_level_o),
        .sweep_interval_o             (sweep_interval_o),
        .cfg_done_o                   (cfg_done_o),
        .run_start_pulse_o            (run_start_pulse_o),
        .run_done_clr_pulse_o         (run_done_clr_pulse_o),
        .num_sweeps_o                 (num_sweeps_o),
        .num_majority_o               (num_majority_o),
        .cfg_req_valid_o              (cfg_req_valid_o),
        .cfg_req_ready_i              (cfg_req_ready_i),
        .cfg_req_o                    (cfg_req_o),
        .cfg_rsp_valid_i              (cfg_rsp_valid_i),
        .cfg_rsp_i                    (cfg_rsp_i)
    );
endmodule
`endif
