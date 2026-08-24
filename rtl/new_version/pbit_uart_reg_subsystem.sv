`ifndef PBIT_UART_REG_SUBSYSTEM
`define PBIT_UART_REG_SUBSYSTEM
import pbit_pkg::*;
// -----------------------------------------------------------------------------
// UART register-access subsystem.
// This replaces the old pbit_uart_host_if direct semantic command decoder.
// UART only produces register reads/writes; pbit_reg_block implements all p-bit
// control and status registers.
// -----------------------------------------------------------------------------
module pbit_uart_reg_subsystem (
    input  logic                                   clk,
    input  logic                                   rst_n,
    
    // UART IO   
    input  logic                                   uart_rx_i,
    output logic                                   uart_tx_o,
        
    output logic                                   uart_rx_busy_o,
    output logic                                   uart_tx_busy_o,
    // External runtime status.        
    input  logic                                   run_busy_i,
    input  logic                                   run_done_i,

    // Snapshot IO        
    input  logic [SNAPSHOT_WIDTH-1:0]              snapshot_flat_i,
    input  logic                                   snapshot_vld_i,
    output logic [SNAPSHOT_ADDR_WIDTH-1:0]         snapshot_addr_o,
    output logic                                   snapshot_latch_pulse_o,
 
     // I0 level IO
    output logic [I0_LEVEL_WIDTH-1:0]              i0_level_o[SWEEP_ROUND_NUM],

    // Sweep interval IO       
    output logic [SWEEP_INTERVAL_WIDTH-1:0]        sweep_interval_o[SWEEP_ROUND_NUM],

    // Global control    
    output logic                                   glb_soft_rstn_o,
    output logic                                   cfg_done_o,
    output logic                                   run_start_pulse_o,
    output logic                                   run_done_clr_pulse_o,
    output logic [NUM_SWEEP_WIDTH-1:0]             num_sweeps_o,
    output logic [NUM_MAJORITY_WIDTH-1:0]          num_majority_o,
       
    // Node backend configuration   
    output logic [NODE_CFG_W-1:0]                  global_node_cfg_o,
    output logic [NODE_SEED_WIDTH-1:0]             global_node_seed_o,
    output logic                                   global_node_cfg_vld_o,
    output logic                                   global_node_seed_vld_o,
  
    output logic [NODE_CFG_W-1:0]                  row_node_cfg_o[ROWS],
    output logic [NODE_SEED_WIDTH-1:0]             row_node_seed_o[SEED_ROWS],
    output logic [ROWS-1:0]                        row_node_cfg_vld_o,
    output logic [SEED_ROWS-1:0]                   row_node_seed_vld_o,

    output logic                                   local_node_cfg_we_pulse_o,
    output logic                                   local_node_cfg_clr_pulse_o,
    output logic                                   local_node_seed_we_pulse_o,
    output logic                                   local_node_seed_clr_pulse_o,
    output logic [TARGET_MODE_WIDTH-1:0]           node_target_mode_o,
    output logic [NODE_TARGET_ROW_WIDTH-1:0]       node_row_o,
    output logic [NODE_TARGET_COL_WIDTH-1:0]       node_col_o,
    output logic [NODE_CFG_PACKED_WIDTH-1:0]       local_node_cfg_o,
    output logic [NODE_SEED_WIDTH-1:0]             local_node_seed_o,
    output logic                                   clr_local_all_pulse_o,
         
    output logic                                   node_load_pulse_o,
   
    // Edge configuration   
    output logic                                   cfg_edge_we_pulse_o,
    output logic                                   cfg_edge_clr_pulse_o,
    output logic [EDGE_TYPE_WIDTH-1:0]             cfg_edge_type_o,
    output logic [EDGE_TARGET_ROW_WIDTH-1:0]       cfg_edge_row_o,
    output logic [EDGE_TARGET_COL_WIDTH-1:0]       cfg_edge_col_o,
    output logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]    cfg_edge_prob_o,
    output logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]    cfg_edge_sign_o,
    output logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0]   cfg_edge_valid_o,
   
    //Node readback IO   
    input  logic [NODE_CFG_W-1:0]                  node_rdata_cfg_i,
    input  logic [NODE_SEED_WIDTH-1:0]             node_rdata_seed_i,
    output logic                                   node_rdata_cfg_pulse_o,
    output logic                                   node_rdata_seed_pulse_o,
   
    //Edge readback IO   
    input  logic [EDGE_RDATA_PACKED_WIDTH-1:0]     edge_rdata_cfg_i,
    output logic                                   edge_rdata_pulse_o
  
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
        .clk                         (clk),
        .rst_n                       (rst_n),

        .reg_wr_en_i                 (reg_wr_en_w),
        .reg_rd_en_i                 (reg_rd_en_w),
        .reg_addr_i                  (reg_addr_w),
        .reg_wdata_i                 (reg_wdata_w),
        .reg_rdata_o                 (reg_rdata_w),
        .reg_access_error_o          (reg_access_error_w),

        .run_busy_i                  (run_busy_i),
        .run_done_i                  (run_done_i),
        .uart_frame_err_pulse_i      (uart_frame_err_pulse_w),
        .uart_overflow_pulse_i       (uart_overflow_pulse_w),


        .snapshot_flat_i             (snapshot_flat_i),
        .snapshot_vld_i              (snapshot_vld_i),
        .snapshot_addr_o             (snapshot_addr_o),
        .snapshot_latch_pulse_o      (snapshot_latch_pulse_o),

        .i0_level_o                  (i0_level_o),

        .sweep_interval_o            (sweep_interval_o),
        
        .glb_soft_rstn_o             (glb_soft_rstn_o),
        .cfg_done_o                  (cfg_done_o),
        .run_start_pulse_o           (run_start_pulse_o),
        .run_done_clr_pulse_o        (run_done_clr_pulse_o),
        .num_sweeps_o                (num_sweeps_o),
        .num_majority_o              (num_majority_o),

        .global_node_cfg_o           (global_node_cfg_o),
        .global_node_seed_o          (global_node_seed_o),
        .global_node_cfg_vld_o       (global_node_cfg_vld_o),
        .global_node_seed_vld_o      (global_node_seed_vld_o),

        .row_node_cfg_o              (row_node_cfg_o),
        .row_node_seed_o             (row_node_seed_o),
        .row_node_cfg_vld_o          (row_node_cfg_vld_o),
        .row_node_seed_vld_o         (row_node_seed_vld_o),

        .local_node_cfg_we_pulse_o   (local_node_cfg_we_pulse_o),
        .local_node_cfg_clr_pulse_o  (local_node_cfg_clr_pulse_o),
        .local_node_seed_we_pulse_o  (local_node_seed_we_pulse_o),
        .local_node_seed_clr_pulse_o (local_node_seed_clr_pulse_o),
        .node_target_mode_o          (node_target_mode_o),
        .node_row_o                  (node_row_o),
        .node_col_o                  (node_col_o),
        .local_node_cfg_o            (local_node_cfg_o),
        .local_node_seed_o           (local_node_seed_o),
        .clr_local_all_pulse_o       (clr_local_all_pulse_o),

        .node_load_pulse_o           (node_load_pulse_o),

        .cfg_edge_we_pulse_o         (cfg_edge_we_pulse_o),
        .cfg_edge_clr_pulse_o        (cfg_edge_clr_pulse_o),
        .cfg_edge_type_o             (cfg_edge_type_o),
        .cfg_edge_row_o              (cfg_edge_row_o),
        .cfg_edge_col_o              (cfg_edge_col_o),
        .cfg_edge_prob_o             (cfg_edge_prob_o),
        .cfg_edge_sign_o             (cfg_edge_sign_o),
        .cfg_edge_valid_o            (cfg_edge_valid_o),

        .node_rdata_cfg_i            (node_rdata_cfg_i),
        .node_rdata_seed_i           (node_rdata_seed_i),
        .node_rdata_cfg_pulse_o      (node_rdata_cfg_pulse_o),
        .node_rdata_seed_pulse_o     (node_rdata_seed_pulse_o),

        .edge_rdata_cfg_i            (edge_rdata_cfg_i),
        .edge_rdata_pulse_o          (edge_rdata_pulse_o)
    );
endmodule
`endif
