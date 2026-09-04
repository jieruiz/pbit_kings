`ifndef PBIT_TOP
`define PBIT_TOP
import pbit_pkg::*;
module pbit_top (
    input  logic clk,
    input  logic rst_n,

    input  logic uart_rx_i,
    output logic uart_tx_o
);

    logic                                   uart_rx_w;
    logic                                   uart_tx_w;
    logic                                   uart_rx_busy_w;
    logic                                   uart_tx_busy_w;

    logic                                   run_busy_w;
    logic                                   run_done_w;

    logic [SNAPSHOT_WIDTH-1:0]              snapshot_flat_w;
    logic                                   snapshot_vld_w;
    logic [SNAPSHOT_ADDR_WIDTH-1:0]         snapshot_addr_w;
    logic                                   snapshot_latch_pulse_w;

    logic [I0_LEVEL_WIDTH-1:0]              i0_level_arr_w[SWEEP_ROUND_NUM];
    logic [I0_LEVEL_WIDTH-1:0]              i0_level_w;

    logic [SWEEP_INTERVAL_WIDTH-1:0]        sweep_interval_w[SWEEP_ROUND_NUM];

    logic                                   glb_soft_rstn_w;
    logic                                   cfg_done_w;
    logic                                   run_start_pulse_w;
    logic                                   run_done_clr_pulse_w;
    logic [NUM_SWEEP_WIDTH-1:0]             num_sweeps_w;
    logic [NUM_MAJORITY_WIDTH-1:0]          num_majority_w;

    logic [NODE_CFG_W-1:0]                  global_node_cfg_w;
    logic [NODE_SEED_WIDTH-1:0]             global_node_seed_w;
    logic                                   global_node_cfg_vld_w;
    logic                                   global_node_seed_vld_w;

    logic [NODE_CFG_W-1:0]                  row_node_cfg_w[ROWS];
    logic [NODE_SEED_WIDTH-1:0]             row_node_seed_w[SHARED_ROWS];
    logic [ROWS-1:0]                        row_node_cfg_vld_w;
    logic [SHARED_ROWS-1:0]                 row_node_seed_vld_w;

    logic                                   local_node_cfg_we_pulse_w;
    logic                                   local_node_cfg_clr_pulse_w;
    logic                                   local_node_seed_we_pulse_w;
    logic                                   local_node_seed_clr_pulse_w;
    logic [TARGET_MODE_WIDTH-1:0]           node_target_mode_w;
    logic [NODE_TARGET_ROW_WIDTH-1:0]       node_row_w;
    logic [NODE_TARGET_COL_WIDTH-1:0]       node_col_w;
    logic [NODE_CFG_PACKED_WIDTH-1:0]       local_node_cfg_w;
    logic [NODE_SEED_WIDTH-1:0]             local_node_seed_w;
    logic                                   clr_local_all_pulse_w;

    logic                                   node_load_pulse_w;

    logic                                   cfg_edge_we_pulse_w;
    logic                                   cfg_edge_clr_pulse_w;
    logic [EDGE_TYPE_WIDTH-1:0]             cfg_edge_type_w;
    logic [EDGE_TARGET_ROW_WIDTH-1:0]       cfg_edge_row_w;
    logic [EDGE_TARGET_COL_WIDTH-1:0]       cfg_edge_col_w;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]    cfg_edge_prob_w;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]    cfg_edge_sign_w;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0]   cfg_edge_valid_w;

    logic [NODE_CFG_W-1:0]                  node_rdata_cfg_w;
    logic [NODE_SEED_WIDTH-1:0]             node_rdata_seed_w;
    logic                                   node_rdata_cfg_pulse_w;
    logic                                   node_rdata_seed_pulse_w;

    logic [EDGE_RDATA_PACKED_WIDTH-1:0]     edge_rdata_cfg_w;
    logic                                   edge_rdata_pulse_w;

    logic                                   all_done_c0_w;
    logic                                   all_done_c1_w;
    logic                                   all_done_c2_w;
    logic                                   all_done_c3_w;
    logic                                   phase_start_w;
    logic                                   phase_start_c0_w;
    logic                                   phase_start_c1_w;
    logic                                   phase_start_c2_w;
    logic                                   phase_start_c3_w;
    logic [3:0]                             current_phase_w;

    assign uart_rx_w = uart_rx_i;
    assign uart_tx_o = uart_tx_w;
    assign phase_start_w = phase_start_c0_w | phase_start_c1_w | phase_start_c2_w | phase_start_c3_w;
    
    pbit_uart_reg_subsystem u_uart_reg_subsystem(
        .clk(clk),
        .rst_n(rst_n),

        .uart_rx_i(uart_rx_w),
        .uart_tx_o(uart_tx_w),

        .uart_rx_busy_o(uart_rx_busy_w),
        .uart_tx_busy_o(uart_tx_busy_w),

        .run_busy_i(run_busy_w),
        .run_done_i(run_done_w),

        .snapshot_flat_i(snapshot_flat_w),
        .snapshot_vld_i(snapshot_vld_w),
        .snapshot_addr_o(snapshot_addr_w),
        .snapshot_latch_pulse_o(snapshot_latch_pulse_w),

        .i0_level_o(i0_level_arr_w),

        .sweep_interval_o(sweep_interval_w),

        .glb_soft_rstn_o(glb_soft_rstn_w),
        .cfg_done_o(cfg_done_w),
        .run_start_pulse_o(run_start_pulse_w),
        .run_done_clr_pulse_o(run_done_clr_pulse_w),
        .num_sweeps_o(num_sweeps_w),
        .num_majority_o(num_majority_w),

        .global_node_cfg_o(global_node_cfg_w),
        .global_node_seed_o(global_node_seed_w),
        .global_node_cfg_vld_o(global_node_cfg_vld_w),
        .global_node_seed_vld_o(global_node_seed_vld_w),

        .row_node_cfg_o(row_node_cfg_w),
        .row_node_seed_o(row_node_seed_w),
        .row_node_cfg_vld_o(row_node_cfg_vld_w),
        .row_node_seed_vld_o(row_node_seed_vld_w),

        .local_node_cfg_we_pulse_o(local_node_cfg_we_pulse_w),
        .local_node_cfg_clr_pulse_o(local_node_cfg_clr_pulse_w),
        .local_node_seed_we_pulse_o(local_node_seed_we_pulse_w),
        .local_node_seed_clr_pulse_o(local_node_seed_clr_pulse_w),
        .node_target_mode_o(node_target_mode_w),
        .node_row_o(node_row_w),
        .node_col_o(node_col_w),
        .local_node_cfg_o(local_node_cfg_w),
        .local_node_seed_o(local_node_seed_w),
        .clr_local_all_pulse_o(clr_local_all_pulse_w),

        .node_load_pulse_o(node_load_pulse_w),

        .cfg_edge_we_pulse_o(cfg_edge_we_pulse_w),
        .cfg_edge_clr_pulse_o(cfg_edge_clr_pulse_w),
        .cfg_edge_type_o(cfg_edge_type_w),
        .cfg_edge_row_o(cfg_edge_row_w),
        .cfg_edge_col_o(cfg_edge_col_w),
        .cfg_edge_prob_o(cfg_edge_prob_w),
        .cfg_edge_sign_o(cfg_edge_sign_w),
        .cfg_edge_valid_o(cfg_edge_valid_w),

        .node_rdata_cfg_i(node_rdata_cfg_w),
        .node_rdata_seed_i(node_rdata_seed_w),
        .node_rdata_cfg_pulse_o(node_rdata_cfg_pulse_w),
        .node_rdata_seed_pulse_o(node_rdata_seed_pulse_w),

        .edge_rdata_cfg_i(edge_rdata_cfg_w),
        .edge_rdata_pulse_o(edge_rdata_pulse_w)
    );

    pbit_array_kings u_pbit_array_kings (
        .clk                    (clk),
        .rst_n                  (rst_n),
  
        .phase_start_i          (phase_start_w),

        .current_phase_i        (current_phase_w),

        .i0_level_i             (i0_level_w),

        .snapshot_addr_i        (snapshot_addr_w),
        .snapshot_latch_pulse_i (snapshot_latch_pulse_w),
        .snapshot_flat_o        (snapshot_flat_w),
        .snapshot_vld_o         (snapshot_vld_w),

        .glb_soft_rstn_i        (glb_soft_rstn_w),
        .num_majority_i         (num_majority_w),

        .global_node_cfg_i      (global_node_cfg_w),
        .global_node_seed_i     (global_node_seed_w),
        .global_node_cfg_vld_i  (global_node_cfg_vld_w),
        .global_node_seed_vld_i  (global_node_seed_vld_w),

        .row_node_cfg_i         (row_node_cfg_w),
        .row_node_seed_i        (row_node_seed_w),
        .row_node_cfg_vld_i     (row_node_cfg_vld_w),
        .row_node_seed_vld_i    (row_node_seed_vld_w),

        .local_node_cfg_we_pulse_i   (local_node_cfg_we_pulse_w),
        .local_node_cfg_clr_pulse_i  (local_node_cfg_clr_pulse_w),
        .local_node_seed_we_pulse_i  (local_node_seed_we_pulse_w),
        .local_node_seed_clr_pulse_i (local_node_seed_clr_pulse_w),
        .node_target_mode_i          (node_target_mode_w),
        .node_row_i                  (node_row_w),
        .node_col_i                  (node_col_w),
        .local_node_cfg_i            (local_node_cfg_w),
        .local_node_seed_i           (local_node_seed_w),
        .clr_local_all_pulse_i       (clr_local_all_pulse_w),

        .node_load_pulse_i      (node_load_pulse_w),

        .cfg_edge_we_pulse_i    (cfg_edge_we_pulse_w),
        .cfg_edge_clr_pulse_i   (cfg_edge_clr_pulse_w),
        .cfg_edge_type_i        (cfg_edge_type_w),
        .cfg_edge_row_i         (cfg_edge_row_w),
        .cfg_edge_col_i         (cfg_edge_col_w),
        .cfg_edge_prob_i        (cfg_edge_prob_w),
        .cfg_edge_sign_i        (cfg_edge_sign_w),
        .cfg_edge_valid_i       (cfg_edge_valid_w),

        .node_rdata_cfg_pulse_i (node_rdata_cfg_pulse_w),
        .node_rdata_seed_pulse_i(node_rdata_seed_pulse_w),
        .node_rdata_cfg_o       (node_rdata_cfg_w),
        .node_rdata_seed_o      (node_rdata_seed_w),

        .edge_rdata_pulse_i     (edge_rdata_pulse_w),
        .edge_rdata_cfg_o       (edge_rdata_cfg_w),

        .all_done_c0_o          (all_done_c0_w),
        .all_done_c1_o          (all_done_c1_w),
        .all_done_c2_o          (all_done_c2_w),
        .all_done_c3_o          (all_done_c3_w)
    );

    phase_ctrl_4color u_phase_ctrl_4color (
        .clk                  (clk),
        .rst_n                (rst_n),
        .glb_soft_rstn_i      (glb_soft_rstn_w),
   
        .cfg_done_i           (cfg_done_w),
        .run_start_pulse_i    (run_start_pulse_w),
        .run_done_clr_pulse_i (run_done_clr_pulse_w),  
        .num_sweeps_i         (num_sweeps_w),
   
        .i0_level_i           (i0_level_arr_w),
   
        .sweep_interval_i     (sweep_interval_w),
   
        .all_done_c0_i        (all_done_c0_w),
        .all_done_c1_i        (all_done_c1_w),
        .all_done_c2_i        (all_done_c2_w),
        .all_done_c3_i        (all_done_c3_w),
   
        .phase_start_c0_o     (phase_start_c0_w),
        .phase_start_c1_o     (phase_start_c1_w),
        .phase_start_c2_o     (phase_start_c2_w),
        .phase_start_c3_o     (phase_start_c3_w),
   
        .current_phase_o      (current_phase_w),

        .i0_level_o           (i0_level_w),
   
        .run_busy_o           (run_busy_w),
        .run_done_o           (run_done_w)
    );

endmodule
`endif
