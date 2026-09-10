`timescale 1ns/1ps
import pbit_pkg::*;
// Test-only equivalent of pbit_top. The only added logic is a bus-master mux.
// UART mode uses the production UART master; bus mode bypasses serialization,
// not register legality checks, configuration routing, banks or node logic.
module chimera_problem_harness (
    input logic clk, rst_n, uart_mode, rx,
    output wire tx,
    input logic wr_en, rd_en,
    input logic [15:0] addr,
    input logic [31:0] wdata,
    output wire [31:0] rdata,
    output wire access_error, cfg_busy, run_busy, run_done,
    output wire run_accept, sweep_done, phase_start, phase,
    output wire [I0_LEVEL_WIDTH-1:0] i0,
    output wire [N_SPIN-1:0] spins,
    output wire [BANK_ROWS*BANK_COLS-1:0] bank_done
);
    wire uart_wr, uart_rd;
    wire [15:0] uart_addr;
    wire [31:0] uart_wdata;
    wire frame_error, overflow;
    wire [SNAPSHOT_WIDTH-1:0] snapshot;
    wire snapshot_vld, snapshot_latch, snapshot_clr;
    wire [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr;
    wire [I0_LEVEL_WIDTH-1:0] levels [SWEEP_ROUND_NUM];
    wire [SWEEP_INTERVAL_WIDTH-1:0] intervals [SWEEP_ROUND_NUM];
    wire cfg_done, run_start, done_clr;
    wire [NUM_SWEEP_WIDTH-1:0] num_sweeps;
    wire [NUM_MAJORITY_WIDTH-1:0] num_majority;
    wire req_valid, req_ready, rsp_valid, all_done;
    wire cfg_array_req_t req;
    wire cfg_rsp_t rsp;

    pbit_uart_reg_master u_uart (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(rx), .uart_tx_o(tx),
        .reg_wr_en_o(uart_wr), .reg_rd_en_o(uart_rd),
        .reg_addr_o(uart_addr), .reg_wdata_o(uart_wdata),
        .reg_rdata_i(rdata), .reg_access_error_i(access_error),
        .uart_frame_err_pulse_o(frame_error), .uart_overflow_pulse_o(overflow),
        .uart_rx_busy_o(), .uart_tx_busy_o()
    );
    pbit_reg_block u_regs (
        .clk(clk), .rst_n(rst_n),
        .reg_wr_en_i(uart_mode ? uart_wr : wr_en),
        .reg_rd_en_i(uart_mode ? uart_rd : rd_en),
        .reg_addr_i(uart_mode ? uart_addr : addr),
        .reg_wdata_i(uart_mode ? uart_wdata : wdata),
        .reg_rdata_o(rdata), .reg_access_error_o(access_error),
        .run_busy_i(run_busy), .run_done_i(run_done),
        .uart_frame_err_pulse_i(frame_error), .uart_overflow_pulse_i(overflow),
        .snapshot_flat_i(snapshot), .snapshot_vld_i(snapshot_vld),
        .snapshot_addr_o(snapshot_addr), .snapshot_latch_pulse_o(snapshot_latch),
        .snapshot_valid_clr_o(snapshot_clr), .i0_level_o(levels),
        .sweep_interval_o(intervals), .cfg_done_o(cfg_done),
        .run_start_pulse_o(run_start), .run_done_clr_pulse_o(done_clr),
        .num_sweeps_o(num_sweeps), .num_majority_o(num_majority),
        .cfg_req_valid_o(req_valid), .cfg_req_ready_i(req_ready), .cfg_req_o(req),
        .cfg_rsp_valid_i(rsp_valid), .cfg_rsp_i(rsp)
    );
    phase_control u_phase (
        .clk(clk), .rst_n(rst_n), .cfg_done_i(cfg_done),
        .run_start_pulse_i(run_start), .run_done_clr_pulse_i(done_clr),
        .num_sweeps_i(num_sweeps), .i0_level_i(levels), .sweep_interval_i(intervals),
        .all_phase_done_i(all_done), .phase_start_o(phase_start), .phase_o(phase),
        .i0_level_o(i0), .run_busy_o(run_busy), .run_done_o(run_done)
    );
    pbit_array_chimera u_array (
        .clk(clk), .rst_n(rst_n), .cfg_req_valid_i(req_valid),
        .cfg_req_ready_o(req_ready), .cfg_req_i(req),
        .cfg_rsp_valid_o(rsp_valid), .cfg_rsp_o(rsp),
        .phase_start_i(phase_start), .phase_i(phase), .i0_level_i(i0),
        .num_majority_i(num_majority), .all_phase_done_o(all_done),
        .snapshot_addr_i(snapshot_addr), .snapshot_latch_pulse_i(snapshot_latch),
        .snapshot_valid_clr_i(snapshot_clr), .snapshot_flat_o(snapshot),
        .snapshot_vld_o(snapshot_vld)
    );
    assign cfg_busy = u_regs.cfg_busy_q;
    assign run_accept = u_phase.run_accept_w;
    assign sweep_done = u_phase.sweep_done_w;
    assign spins = u_array.spin_flat_w[N_SPIN-1:0];
    for (genvar r=0; r<BANK_ROWS; r++) begin : ROW
        for (genvar c=0; c<BANK_COLS; c++) begin : COL
            assign bank_done[r*BANK_COLS+c] = u_array.bank_phase_done_w[r][c];
        end
    end
endmodule
