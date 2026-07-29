`ifndef PBIT_REG_BLOCK
`define PBIT_REG_BLOCK
import pbit_pkg::*;
// -----------------------------------------------------------------------------
// pbit_reg_block
// Unified register table for UART/APB/AXI-lite style access.
//
// Node configuration model in this version:
//   - One software-visible staging set: NODE_TARGET / NODE_CFG / NODE_SEED
//     / NODE_FIELD_WE / NODE_CMD.
//   - APPLY_CFG updates one backend scope selected by TARGET_MODE:
//       GLOBAL, ROW, or LOCAL.
//   - NODE_FIELD_WE is only the current apply write mask.
//   - Backend *_valid bits decide whether a field participates in priority.
//   - Priority per field: LOCAL > ROW > GLOBAL > DEFAULT.
//   - Seed mode is removed. NODE_SEED is the exact seed value saved/loaded.
// -----------------------------------------------------------------------------
module pbit_reg_block (
    input  logic                                    clk,
    input  logic                                    rst_n,

    // Simple 32-bit register bus. Address is byte address, 4-byte aligned.
    input  logic                                    reg_wr_en_i,
    input  logic                                    reg_rd_en_i,
    input  logic [15:0]                             reg_addr_i,
    input  logic [31:0]                             reg_wdata_i,
    output logic [31:0]                             reg_rdata_o,
           
    // External runtime status.           
    input  logic                                    run_busy_i,
    input  logic                                    run_done_i,
    input  logic                                    uart_frame_err_pulse_i,
    input  logic                                    uart_overflow_pulse_i,
           
    // Snapshot IO           
    input  logic [SNAPSHOT_WIDTH-1:0]               snapshot_flat_i,
    input  logic                                    snapshot_vld_i,
    output logic [SNAPSHOT_ADDR_WIDTH-1:0]          snapshot_addr_o,
    output logic                                    snapshot_latch_pulse_o,

    // I0 level IO
    output logic [I0_LEVEL_WIDTH-1:0]               i0_level_o[SWEEP_ROUND_NUM],
       
    // Sweep interval IO       
    output logic [SWEEP_INTERVAL_WIDTH-1:0]         sweep_interval_o[SWEEP_ROUND_NUM],
    
    // Global control outputs.        
    output logic                                    glb_soft_rstn_o,
    output logic                                    cfg_done_o,
    output logic                                    run_start_pulse_o,
    output logic                                    run_done_clr_pulse_o,
    output logic [NUM_SWEEP_WIDTH-1:0]              num_sweeps_o,
    output logic [NUM_MAJORITY_WIDTH-1:0]           num_majority_o,

    // Node backend configuration
    output logic [NODE_CFG_W-1:0]                   global_node_cfg_o,
    output logic [NODE_SEED_WIDTH-1:0]              global_node_seed_o,
    output logic                                    global_node_cfg_vld_o,
 
    output logic [NODE_CFG_W-1:0]                   row_node_cfg_o[ROWS],
    output logic [NODE_SEED_WIDTH-1:0]              row_node_seed_o[ROWS],
    output logic [ROWS-1:0]                         row_node_cfg_vld_o,
 
    output logic                                    local_node_we_pulse_o,
    output logic                                    local_node_clr_pulse_o,
    output logic [TARGET_MODE_WIDTH-1:0]            cfg_node_target_mode_o,//used in node readback
    output logic [NODE_TARGET_ROW_WIDTH-1:0]        cfg_node_row_o,
    output logic [NODE_TARGET_COL_WIDTH-1:0]        cfg_node_col_o,
    output logic [NODE_CFG_PACKED_WIDTH-1:0]        local_node_cfg_o,
    output logic [NODE_SEED_WIDTH-1:0]              local_node_seed_o,
    output logic                                    clr_local_all_pulse_o,
           
    output logic                                    node_load_pulse_o,

    // Edge configuration
    output logic                                    cfg_edge_we_pulse_o,
    output logic                                    cfg_edge_clr_pulse_o,
    output logic [EDGE_TYPE_WIDTH-1:0]              cfg_edge_type_o,
    output logic [EDGE_TARGET_ROW_WIDTH-1:0]        cfg_edge_row_o,
    output logic [EDGE_TARGET_COL_WIDTH-1:0]        cfg_edge_col_o,
    output logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]     cfg_edge_prob_o,
    output logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]     cfg_edge_sign_o,
    output logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0]    cfg_edge_valid_o,

    //Node readback IO
    input  logic [NODE_CFG_W-1:0]                   node_rdata_cfg_i,
    input  logic [NODE_RDATA_SEED_WIDTH-1:0]        node_rdata_seed_i,
    output logic                                    node_rdata_pulse_o,

    //Edge readback IO
    input  logic [EDGE_RDATA_PACKED_WIDTH-1:0]      edge_rdata_cfg_i,
    output logic                                    edge_rdata_pulse_o
);

    // -------------------------------------------------------------------------
    // Node staging registers.
    // -------------------------------------------------------------------------
    logic [NODE_TARGET_PACKED_WIDTH-1:0] node_target_q, node_target_d;// target_mode(2bit) + row(6bit) + col(6bit)
    logic                                node_target_en;
    logic [NODE_CFG_PACKED_WIDTH-1:0]    node_cfg_q, node_cfg_d;// init_valid(1bit) + seed_valid(1bit) + clamp_valid(1bit) + bias_valid(1bit)
                                                   // + init_spin(1bit) + clamp_en(1bit) + clamp_spin(1bit) + bias_sign(1bit) + bias_prob(4bit)
    logic                                node_cfg_en;
    logic [NODE_SEED_PACKED_WIDTH-1:0]   node_seed_q, node_seed_d;
    logic                                node_seed_en;

    assign cfg_node_target_mode_o = node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB];
    assign cfg_node_row_o         = node_target_q[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB];
    assign cfg_node_col_o         = node_target_q[NODE_TARGET_COL_PACKED_MSB:NODE_TARGET_COL_PACKED_LSB];
    assign local_node_cfg_o       = node_cfg_q;
    assign local_node_seed_o      = node_seed_q[NODE_SEED_PACKED_MSB:NODE_SEED_PACKED_LSB];

    // -------------------------------------------------------------------------
    // Edge staging registers
    // -------------------------------------------------------------------------
    logic [EDGE_TYPE_WIDTH-1:0]           cfg_edge_type_q, cfg_edge_type_d;
    logic [EDGE_TARGET_ROW_WIDTH-1:0]     cfg_edge_row_q, cfg_edge_row_d;
    logic                                 cfg_edge_row_en;
    logic [EDGE_TARGET_COL_WIDTH-1:0]     cfg_edge_col_q, cfg_edge_col_d;
    logic                                 cfg_edge_col_en;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  cfg_edge_prob_q, cfg_edge_prob_d;
    logic                                 cfg_edge_prob_en;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]  cfg_edge_sign_q, cfg_edge_sign_d;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] cfg_edge_valid_q, cfg_edge_valid_d;

    assign cfg_edge_type_o     = cfg_edge_type_q;
    assign cfg_edge_row_o      = cfg_edge_row_q;
    assign cfg_edge_col_o      = cfg_edge_col_q;
    assign cfg_edge_prob_o    = cfg_edge_prob_q;
    assign cfg_edge_sign_o     = cfg_edge_sign_q;
    assign cfg_edge_valid_o    = cfg_edge_valid_q;

    // -------------------------------------------------------------------------
    // Backend node configuration registers
    // -------------------------------------------------------------------------
    logic [NODE_CFG_W-1:0]             global_node_cfg_q, global_node_cfg_d;
    logic                              global_node_cfg_en;
    logic [NODE_SEED_WIDTH-1:0]        global_node_seed_q, global_node_seed_d;
    logic                              global_node_seed_en;
    logic                              global_node_cfg_vld_q, global_node_cfg_vld_d;

    logic [NODE_CFG_W-1:0]             row_node_cfg_q  [0:ROWS-1], row_node_cfg_d[0:ROWS-1];
    logic                              row_node_cfg_en [0:ROWS-1];
    logic [NODE_SEED_WIDTH-1:0]        row_node_seed_q [0:ROWS-1], row_node_seed_d[0:ROWS-1];
    logic                              row_node_seed_en[0:ROWS-1];
    logic [ROWS-1:0]                   row_node_cfg_vld_q, row_node_cfg_vld_d;

    assign global_node_cfg_o  = global_node_cfg_q;
    assign global_node_seed_o = global_node_seed_q;
    assign global_node_cfg_vld_o = global_node_cfg_vld_q;

    genvar g;
    generate
        for (g = 0; g < ROWS; g = g + 1) begin : GEN_ROW_NODE_CFG
            assign row_node_cfg_o [g] = row_node_cfg_q[g];
            assign row_node_seed_o[g] = row_node_seed_q[g];
        end
    endgenerate
    assign row_node_cfg_vld_o = row_node_cfg_vld_q;

    // -------------------------------------------------------------------------
    // Global configuration registers.
    // -------------------------------------------------------------------------
    logic [GLOBAL_CFG_PACKED_WIDTH-1:0] global_cfg_q, global_cfg_d;
    logic                               global_cfg_en;

    assign num_majority_o    = global_cfg_q[NUM_MAJORITY_PACKED_MSB:NUM_MAJORITY_PACKED_LSB];
    assign num_sweeps_o      = global_cfg_q[NUM_SWEEP_PACKED_MSB:NUM_SWEEP_PACKED_LSB];

    // -------------------------------------------------------------------------
    // SNAPSHOT addr registers.
    // -------------------------------------------------------------------------
    logic [SNAPSHOT_ADDR_PACKED_WIDTH-1:0] snapshot_addr_q, snapshot_addr_d;

    assign snapshot_addr_o = snapshot_addr_q[SNAPSHOT_ADDR_PACKED_MSB:SNAPSHOT_ADDR_PACKED_LSB];

    // -------------------------------------------------------------------------
    // i0 level registers.
    // -------------------------------------------------------------------------
    logic [I0_LEVEL_PACKED_WIDTH-1:0] i0_level_q[I0_LEVEL_REG_NUM], i0_level_d;
    logic [I0_LEVEL_REG_NUM-1:0]      i0_level_en;
    generate
        for(g = 0; g < I0_LEVEL_REG_NUM; g = g + 1) begin : I0_LEVEL_REG_ASSIGN
            assign i0_level_o[g*4+0] = i0_level_q[g][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB];
            assign i0_level_o[g*4+1] = i0_level_q[g][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB];
            assign i0_level_o[g*4+2] = i0_level_q[g][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB];
            assign i0_level_o[g*4+3] = i0_level_q[g][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // sweep interval registers.
    // -------------------------------------------------------------------------
    logic [SWEEP_INTERVAL_PACKED_WIDTH-1:0] sweep_interval_q[SWEEP_INTERVAL_REG_NUM], sweep_interval_d;
    logic [SWEEP_INTERVAL_REG_NUM-1:0]      sweep_interval_en;
    generate
        for(g = 0; g < SWEEP_INTERVAL_REG_NUM; g = g + 1) begin : SWEEP_INTERVAL_REG_ASSIGN
            assign sweep_interval_o[g*2+0] = sweep_interval_q[g][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB];
            assign sweep_interval_o[g*2+1] = sweep_interval_q[g][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // ERROR_STATUS registers.
    // -------------------------------------------------------------------------
    logic uart_frame_err_pulse_w;
    logic uart_overflow_pulse_w;
    logic [ERROR_STATUS_PACKED_WIDTH-1:0] error_status_q, error_status_d;

    assign uart_frame_err_pulse_w = uart_frame_err_pulse_i;
    assign uart_overflow_pulse_w = uart_overflow_pulse_i;
    // -------------------------------------------------------------------------
    // Global status registers
    // -------------------------------------------------------------------------
    logic [GLOBAL_STATUS_PACKED_WIDTH-1:0] global_status_w;
    logic                                  cfg_done_q, cfg_done_d;
    logic                                  run_busy_w;
    logic                                  run_done_w;//检查是否为电平信号而不是脉冲
    logic                                  node_cfg_done_q, node_cfg_done_d;
    logic                                  edge_cfg_done_q, edge_cfg_done_d;
    logic                                  snapshot_valid_w;
    logic                                  have_error_status_w;

    assign run_busy_w = run_busy_i;
    assign run_done_w = run_done_i;
    assign have_error_status_w = |error_status_q;
    assign cfg_done_o = cfg_done_q;
    assign snapshot_valid_w = snapshot_vld_i;
    assign global_status_w[CFG_DONE_PACKED_MSB:CFG_DONE_PACKED_LSB]             = cfg_done_q;
    assign global_status_w[RUN_BUSY_PACKED_MSB:RUN_BUSY_PACKED_LSB]             = run_busy_w;
    assign global_status_w[RUN_DONE_PACKED_MSB:RUN_DONE_PACKED_LSB]             = run_done_w;
    assign global_status_w[NODE_CFG_DONE_PACKED_MSB:NODE_CFG_DONE_PACKED_LSB]   = node_cfg_done_q;
    assign global_status_w[EDGE_CFG_DONE_PACKED_MSB:EDGE_CFG_DONE_PACKED_LSB]   = edge_cfg_done_q;
    assign global_status_w[SNAPSHOT_VALID_PACKED_MSB:SNAPSHOT_VALID_PACKED_LSB] = snapshot_valid_w;
    assign global_status_w[ERROR_PACKED_MSB:ERROR_PACKED_LSB]                   = have_error_status_w;

    // -------------------------------------------------------------------------
    // Node rdata registers.
    // -------------------------------------------------------------------------
    logic [NODE_CFG_W-1:0]                  node_rdata_cfg_w;
    logic [NODE_RDATA_SEED_WIDTH-1:0]       node_rdata_seed_w;

    assign node_rdata_cfg_w  = node_rdata_cfg_i;
    assign node_rdata_seed_w = node_rdata_seed_i;

    // -------------------------------------------------------------------------
    // Edge rdata registers.
    // -------------------------------------------------------------------------
    logic [EDGE_RDATA_PACKED_WIDTH-1:0] edge_rdata_cfg_w;

    assign edge_rdata_cfg_w = edge_rdata_cfg_i;

    // -------------------------------------------------------------------------
    // SPIN rdata registers.
    // -------------------------------------------------------------------------
    logic [SPIN_RDATA_PACKED_WIDTH-1:0] spin_data_w[SPIN_RDATA_REG_NUM-1:0];
    generate
        for (g = 0; g < SPIN_RDATA_REG_NUM; g++) begin : SPIN_RDATA
            assign spin_data_w[g] = snapshot_flat_i[g*SPIN_RDATA_PACKED_WIDTH +: SPIN_RDATA_PACKED_WIDTH];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Glboal Control registers.
    // -------------------------------------------------------------------------
    logic glb_soft_rstn_w;//pulse
    logic cfg_done_set_pulse_w;
    logic cfg_done_clr_pulse_w;
    logic run_start_pulse_w;        
    logic snapshot_latch_pulse_w;
    logic run_done_clr_pulse_w;
    logic error_clear_pulse_w;

    assign glb_soft_rstn_o        = glb_soft_rstn_w;
    assign run_start_pulse_o      = run_start_pulse_w; 
    assign snapshot_latch_pulse_o = snapshot_latch_pulse_w;
    assign run_done_clr_pulse_o   = run_done_clr_pulse_w;

    // -------------------------------------------------------------------------
    // Node Control registers.
    // -------------------------------------------------------------------------
    logic node_apply_cfg_pulse_w;
    logic local_node_cfg_pulse_w;
    logic node_load_pulse_w;
    logic clr_scope_en_pulse_w;
    logic local_node_clr_pulse_w;
    logic clr_local_all_pulse_w;
    logic node_rdata_pulse_w;

    assign node_load_pulse_o      = node_load_pulse_w;
    assign local_node_we_pulse_o  = local_node_cfg_pulse_w;
    assign local_node_clr_pulse_o = local_node_clr_pulse_w;
    assign clr_local_all_pulse_o  = clr_local_all_pulse_w;
    assign node_rdata_pulse_o     = node_rdata_pulse_w;

    // -------------------------------------------------------------------------
    // Edge Control registers.
    // -------------------------------------------------------------------------
    logic edge_apply_cfg_pulse_w;
    logic cfg_edge_clr_pulse_w;
    logic edge_rdata_pulse_w;

    assign cfg_edge_we_pulse_o  = edge_apply_cfg_pulse_w;
    assign cfg_edge_clr_pulse_o = cfg_edge_clr_pulse_w;
    assign edge_rdata_pulse_o   = edge_rdata_pulse_w;
    
    // -------------------------------------------------------------------------
    // Decode helpers.
    // -------------------------------------------------------------------------
    function automatic logic node_target_mode_valid(
        input [TARGET_MODE_WIDTH-1:0] mode
    );
        case (mode)
            TARGET_MODE_GLOBAL: node_target_mode_valid = 1'b1;
            TARGET_MODE_ROW:    node_target_mode_valid = 1'b1;
            TARGET_MODE_LOCAL:  node_target_mode_valid = 1'b1;
            default:     node_target_mode_valid = 1'b0;
        endcase
    endfunction

    function automatic logic node_target_row_valid(
        input [NODE_TARGET_ROW_WIDTH-1:0] row
    );
        node_target_row_valid = (row < ROWS[NODE_TARGET_ROW_WIDTH-1:0]);
    endfunction

    function automatic logic node_target_col_valid(
        input [NODE_TARGET_COL_WIDTH-1:0] col
    );
        node_target_col_valid = (col < COLS[NODE_TARGET_COL_WIDTH-1:0]);
    endfunction

    function automatic logic edge_target_type_valid(
        input [EDGE_TYPE_WIDTH-1:0] typ
    );
        case (typ)
            EDGE_TYPE_EDGE_H:   edge_target_type_valid = 1'b1;
            EDGE_TYPE_EDGE_V:   edge_target_type_valid = 1'b1;
            EDGE_TYPE_EDGE_DSE: edge_target_type_valid = 1'b1;
            EDGE_TYPE_EDGE_DSW: edge_target_type_valid = 1'b1;
            default:  edge_target_type_valid = 1'b0;
        endcase
    endfunction

    function automatic logic edge_target_row_valid(
        input [EDGE_TYPE_WIDTH-1:0] typ,
        input [EDGE_TARGET_ROW_WIDTH-1:0] row
    );
        edge_target_row_valid = (typ == EDGE_TYPE_EDGE_H)? (row < ROWS[EDGE_TARGET_ROW_WIDTH-1:0]): (row < (ROWS[EDGE_TARGET_ROW_WIDTH-1:0]-1));
    endfunction

    function automatic logic edge_target_col_valid(
        input [EDGE_TYPE_WIDTH-1:0] typ,
        input [EDGE_TARGET_COL_WIDTH-1:0] col
    );
        edge_target_col_valid = (typ == EDGE_TYPE_EDGE_DSW)? (col < COLS[EDGE_TARGET_COL_WIDTH-1:0]): 
                                (typ == EDGE_TYPE_EDGE_V)? (col < COLS[EDGE_TARGET_COL_WIDTH-1:0]):
                                (col < (COLS[EDGE_TARGET_COL_WIDTH-1:0]-1));
    endfunction

    function automatic logic snapshot_addr_valid(
        input [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr
    );
        snapshot_addr_valid = snapshot_addr < SPIN_ADDR_MAX[SNAPSHOT_ADDR_WIDTH-1:0];
    endfunction

    function automatic logic addr_valid(
        input [15:0] addr
    );
        case (addr)
            A_GLOBAL_CTRL,
            A_GLOBAL_CFG,
            A_GLOBAL_STATUS,
            A_ARRAY_PARAM,
            A_ERROR_STATUS,
            A_SNAPSHOT_ADDR,
            A_I0_LEVEL0,
            A_I0_LEVEL1,
            A_I0_LEVEL2,
            A_I0_LEVEL3,
            A_I0_LEVEL4,
            A_I0_LEVEL5,
            A_I0_LEVEL6,
            A_I0_LEVEL7,
            A_I0_LEVEL8,
            A_I0_LEVEL9,
            A_I0_LEVEL10,
            A_I0_LEVEL11,
            A_I0_LEVEL12,
            A_I0_LEVEL13,
            A_I0_LEVEL14,
            A_I0_LEVEL15,
            A_SWEEP_INTERVAL0,
            A_SWEEP_INTERVAL1,
            A_SWEEP_INTERVAL2,
            A_SWEEP_INTERVAL3,
            A_SWEEP_INTERVAL4,
            A_SWEEP_INTERVAL5,
            A_SWEEP_INTERVAL6,
            A_SWEEP_INTERVAL7,
            A_SWEEP_INTERVAL8,
            A_SWEEP_INTERVAL9,
            A_SWEEP_INTERVAL10,
            A_SWEEP_INTERVAL11,
            A_SWEEP_INTERVAL12,
            A_SWEEP_INTERVAL13,
            A_SWEEP_INTERVAL14,
            A_SWEEP_INTERVAL15,
            A_SWEEP_INTERVAL16,
            A_SWEEP_INTERVAL17,
            A_SWEEP_INTERVAL18,
            A_SWEEP_INTERVAL19,
            A_SWEEP_INTERVAL20,
            A_SWEEP_INTERVAL21,
            A_SWEEP_INTERVAL22,
            A_SWEEP_INTERVAL23,
            A_SWEEP_INTERVAL24,
            A_SWEEP_INTERVAL25,
            A_SWEEP_INTERVAL26,
            A_SWEEP_INTERVAL27,
            A_SWEEP_INTERVAL28,
            A_SWEEP_INTERVAL29,
            A_SWEEP_INTERVAL30,
            A_SWEEP_INTERVAL31,
            A_NODE_TARGET,
            A_NODE_CFG,
            A_NODE_SEED,
            A_NODE_CMD,
            A_NODE_RDATA_CFG,
            A_NODE_RDATA_SEED,
            A_EDGE_TARGET,
            A_EDGE_CFG,
            A_EDGE_CMD,
            A_EDGE_RDATA,
            A_SPIN_RDATA0,
            A_SPIN_RDATA1,
            A_SPIN_RDATA2,
            A_SPIN_RDATA3,
            A_SPIN_RDATA4,
            A_SPIN_RDATA5,
            A_SPIN_RDATA6,
            A_SPIN_RDATA7,
            A_SPIN_RDATA8,
            A_SPIN_RDATA9:addr_valid = 1'b1;
            default: addr_valid = 1'b0;
        endcase
    endfunction

    function automatic logic addr_writable(//为节省面积，可写不保证有效
        input [15:0] addr
    );        
        case (addr)
            A_GLOBAL_STATUS,
            A_ARRAY_PARAM,
            A_NODE_RDATA_CFG,
            A_NODE_RDATA_SEED,
            A_EDGE_RDATA,
            A_SPIN_RDATA0,
            A_SPIN_RDATA1,
            A_SPIN_RDATA2,
            A_SPIN_RDATA3,
            A_SPIN_RDATA4,
            A_SPIN_RDATA5,
            A_SPIN_RDATA6,
            A_SPIN_RDATA7,
            A_SPIN_RDATA8,
            A_SPIN_RDATA9: addr_writable = 1'b0;
            default: addr_writable = 1'b1;
        endcase
    endfunction

    function automatic logic addr_readable(//为节省面积，可读不保证有效
        input [15:0] addr
    );
        case (addr)
            A_GLOBAL_CTRL,
            A_NODE_CMD,
            A_EDGE_CMD: addr_readable = 1'b0;
            default: addr_readable = 1'b1;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Register read mux.
    // -------------------------------------------------------------------------
    logic [31:0] reg_rdata_q, reg_rdata_d;
    logic        reg_rdata_en;

    assign reg_rdata_o = reg_rdata_q;
    always @(*) begin : REG_READ_MUX
        case (reg_addr_i)
            A_GLOBAL_CFG:      reg_rdata_d = {{(32-GLOBAL_CFG_PACKED_WIDTH){1'b0}},global_cfg_q};
            A_GLOBAL_STATUS:   reg_rdata_d = {{(32-GLOBAL_STATUS_PACKED_WIDTH){1'b0}},global_status_w};
            A_ARRAY_PARAM:     reg_rdata_d = {N_SPIN_WIDTH'(N_SPIN), COLS_WIDTH'(COLS), ROWS_WIDTH'(ROWS)};
            A_ERROR_STATUS:    reg_rdata_d = {{(32-ERROR_STATUS_PACKED_WIDTH){1'b0}}, error_status_q};
            A_SNAPSHOT_ADDR:   reg_rdata_d = {{(32-SNAPSHOT_ADDR_PACKED_WIDTH){1'b0}}, snapshot_addr_q};

            A_NODE_TARGET:     reg_rdata_d = {{(32-NODE_TARGET_COL_MSB-1){1'b0}},node_target_q[NODE_TARGET_COL_PACKED_MSB:NODE_TARGET_COL_PACKED_LSB],{(NODE_TARGET_COL_LSB-NODE_TARGET_ROW_MSB-1){1'b0}},node_target_q[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB],
                                              {(NODE_TARGET_ROW_LSB-TARGET_MODE_MSB-1){1'b0}},node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB]};
            A_NODE_CFG:        reg_rdata_d = {{(32-NODE_CFG_BIAS_PROB_MSB-1){1'b0}},node_cfg_q[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB],
                                              {(NODE_CFG_INIT_SPIN_LSB-BIAS_VALID_MSB-1){1'b0}},node_cfg_q[BIAS_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB]};
            A_NODE_SEED:       reg_rdata_d = {{(32-NODE_SEED_PACKED_WIDTH){1'b0}},node_seed_q};
            A_NODE_RDATA_CFG:  reg_rdata_d = {{(32-NODE_CFG_W){1'b0}},node_rdata_cfg_w};
            A_NODE_RDATA_SEED: reg_rdata_d = node_rdata_seed_w;
            A_I0_LEVEL0: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[0][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[0][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[0][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[0][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL1: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[1][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[1][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[1][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[1][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL2: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[2][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[2][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[2][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[2][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL3: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[3][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[3][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[3][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[3][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL4: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[4][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[4][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[4][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[4][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL5: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[5][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[5][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[5][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[5][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL6: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[6][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[6][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[6][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[6][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL7: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[7][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[7][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[7][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[7][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL8: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[8][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[8][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[8][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[8][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL9: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[9][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[9][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[9][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[9][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL10: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[10][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[10][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[10][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[10][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL11: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[11][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[11][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[11][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[11][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL12: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[12][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[12][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[12][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[12][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL13: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[13][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[13][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[13][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[13][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL14: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[14][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[14][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[14][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[14][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_I0_LEVEL15: reg_rdata_d = {{(32-I0_LEVEL3_MSB-1){1'b0}},i0_level_q[15][I0_LEVEL3_PACKED_MSB:I0_LEVEL3_PACKED_LSB],{(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}},i0_level_q[15][I0_LEVEL2_PACKED_MSB:I0_LEVEL2_PACKED_LSB],
                                        {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}},i0_level_q[15][I0_LEVEL1_PACKED_MSB:I0_LEVEL1_PACKED_LSB],{(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}},i0_level_q[15][I0_LEVEL0_PACKED_MSB:I0_LEVEL0_PACKED_LSB]};
            A_SWEEP_INTERVAL0: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[0][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[0][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL1: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[1][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[1][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL2: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[2][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[2][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL3: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[3][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[3][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL4: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[4][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[4][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL5: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[5][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[5][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL6: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[6][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[6][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL7: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[7][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[7][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL8: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[8][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[8][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL9: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[9][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[9][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL10: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[10][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[10][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL11: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[11][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[11][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL12: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[12][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[12][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL13: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[13][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[13][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL14: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[14][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[14][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL15: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[15][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[15][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL16: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[16][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[16][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL17: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[17][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[17][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL18: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[18][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[18][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL19: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[19][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[19][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL20: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[20][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[20][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL21: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[21][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[21][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL22: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[22][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[22][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL23: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[23][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[23][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL24: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[24][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[24][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL25: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[25][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[25][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL26: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[26][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[26][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL27: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[27][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[27][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL28: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[28][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[28][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL29: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[29][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[29][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL30: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[30][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[30][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_SWEEP_INTERVAL31: reg_rdata_d = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval_q[31][SWEEP_INTERVAL1_PACKED_MSB:SWEEP_INTERVAL1_PACKED_LSB], {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval_q[31][SWEEP_INTERVAL0_PACKED_MSB:SWEEP_INTERVAL0_PACKED_LSB]};
            A_EDGE_TARGET:     reg_rdata_d = {{(32-EDGE_TARGET_COL_MSB-1){1'b0}},cfg_edge_col_q,{(EDGE_TARGET_COL_LSB-EDGE_TARGET_ROW_MSB-1){1'b0}},cfg_edge_row_q,
                                              {(EDGE_TARGET_ROW_LSB-EDGE_TYPE_MSB-1){1'b0}},cfg_edge_type_q};
            A_EDGE_CFG:        reg_rdata_d = {{(32-EDGE_CFG_PACKED_WIDTH){1'b0}},cfg_edge_prob_q, cfg_edge_sign_q, cfg_edge_valid_q};
            A_EDGE_RDATA:      reg_rdata_d = {{(32-EDGE_RDATA_PACKED_WIDTH){1'b0}},edge_rdata_cfg_w};
            A_SPIN_RDATA0:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[0][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA1:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[1][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA2:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[2][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA3:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[3][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA4:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[4][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA5:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[5][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA6:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[6][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA7:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[7][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA8:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[8][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            A_SPIN_RDATA9:     reg_rdata_d = {{(32-SPIN_RDATA_PACKED_WIDTH){1'b0}},spin_data_w[9][SPIN_RDATA_DATA_PACKED_MSB:SPIN_RDATA_DATA_PACKED_LSB]};
            default:           reg_rdata_d = 32'd0;
        endcase
    end
    assign reg_rdata_en = reg_rd_en_i;

    // -------------------------------------------------------------------------
    // Node staging registers’s d port assignment
    // -------------------------------------------------------------------------
    assign node_target_d  = {reg_wdata_i[NODE_TARGET_COL_MSB:NODE_TARGET_COL_LSB],reg_wdata_i[NODE_TARGET_ROW_MSB:NODE_TARGET_ROW_LSB],reg_wdata_i[TARGET_MODE_MSB:TARGET_MODE_LSB]};
    assign node_target_en = (reg_addr_i == A_NODE_TARGET) && reg_wr_en_i;
    assign node_cfg_d     = {reg_wdata_i[NODE_CFG_BIAS_PROB_MSB:NODE_CFG_INIT_SPIN_LSB], reg_wdata_i[BIAS_VALID_MSB:INIT_VALID_LSB]};
    assign node_cfg_en    = (reg_addr_i == A_NODE_CFG) && reg_wr_en_i;
    assign node_seed_d    = reg_wdata_i[NODE_SEED_MSB:NODE_SEED_LSB];
    assign node_seed_en   = (reg_addr_i == A_NODE_SEED) && reg_wr_en_i;

    // -------------------------------------------------------------------------
    // Edge staging registers's d port assignment
    // -------------------------------------------------------------------------
    assign cfg_edge_type_d  = ((reg_addr_i == A_EDGE_TARGET) && reg_wr_en_i)? reg_wdata_i[EDGE_TYPE_MSB:EDGE_TYPE_LSB]: cfg_edge_type_q;
    assign cfg_edge_row_d   = reg_wdata_i[EDGE_TARGET_ROW_MSB:EDGE_TARGET_ROW_LSB];
    assign cfg_edge_row_en  = (reg_addr_i == A_EDGE_TARGET) && reg_wr_en_i;
    assign cfg_edge_col_d   = reg_wdata_i[EDGE_TARGET_COL_MSB:EDGE_TARGET_COL_LSB];
    assign cfg_edge_col_en  = (reg_addr_i == A_EDGE_TARGET) && reg_wr_en_i;
    assign cfg_edge_prob_d  = reg_wdata_i[EDGE_CFG_EDGE_PROB_MSB:EDGE_CFG_EDGE_PROB_LSB];
    assign cfg_edge_prob_en = (reg_addr_i == A_EDGE_CFG) && reg_wr_en_i;
    assign cfg_edge_sign_d  = ((reg_addr_i == A_EDGE_CFG) && reg_wr_en_i)? reg_wdata_i[EDGE_CFG_EDGE_SIGN_MSB:EDGE_CFG_EDGE_SIGN_LSB]: cfg_edge_sign_q;
    assign cfg_edge_valid_d = ((reg_addr_i == A_EDGE_CFG) && reg_wr_en_i)? reg_wdata_i[EDGE_CFG_EDGE_VALID_MSB:EDGE_CFG_EDGE_VALID_LSB]: cfg_edge_valid_q;

    // -------------------------------------------------------------------------
    // Backend node configuration registers's d port assignment
    // -------------------------------------------------------------------------
    assign global_node_cfg_d[NODE_CFG_INIT_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_INIT_SPIN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[INIT_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB]? 
                                                                                                                              node_cfg_q[NODE_CFG_INIT_SPIN_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB]:
                                                                                                                              global_node_cfg_q[NODE_CFG_INIT_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_INIT_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_cfg_d[NODE_CFG_CLAMP_EN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_EN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? 
                                                                                                                            node_cfg_q[NODE_CFG_CLAMP_EN_PACKED_MSB:NODE_CFG_CLAMP_EN_PACKED_LSB]:
                                                                                                                            global_node_cfg_q[NODE_CFG_CLAMP_EN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_EN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_cfg_d[NODE_CFG_CLAMP_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_SPIN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? 
                                                                                                                                node_cfg_q[NODE_CFG_CLAMP_SPIN_PACKED_MSB:NODE_CFG_CLAMP_SPIN_PACKED_LSB]:
                                                                                                                                global_node_cfg_q[NODE_CFG_CLAMP_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_cfg_d[NODE_CFG_BIAS_SIGN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_SIGN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? 
                                                                                                                              node_cfg_q[NODE_CFG_BIAS_SIGN_PACKED_MSB:NODE_CFG_BIAS_SIGN_PACKED_LSB]:
                                                                                                                              global_node_cfg_q[NODE_CFG_BIAS_SIGN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_SIGN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_cfg_d[NODE_CFG_BIAS_PROB_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_PROB_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? 
                                                                                                                                node_cfg_q[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_BIAS_PROB_PACKED_LSB]:
                                                                                                                                global_node_cfg_q[NODE_CFG_BIAS_PROB_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_PROB_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_cfg_en = node_apply_cfg_pulse_w && (node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_GLOBAL);
    assign global_node_seed_d = node_cfg_q[SEED_VALID_PACKED_MSB:SEED_VALID_PACKED_LSB]? 
                                node_seed_q[NODE_SEED_PACKED_MSB:NODE_SEED_PACKED_LSB]:
                                global_node_seed_q[NODE_SEED_PACKED_MSB:NODE_SEED_PACKED_LSB];
    assign global_node_seed_en = node_apply_cfg_pulse_w && (node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_GLOBAL);
    assign global_node_cfg_vld_d = node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_GLOBAL?
                                   node_apply_cfg_pulse_w? 1'b1:
                                   clr_scope_en_pulse_w? 1'b0:
                                   global_node_cfg_vld_q:
                                   global_node_cfg_vld_q;

    generate
        for (g = 0; g < ROWS; g = g + 1) begin : ROW_NODE_CFG
            assign row_node_cfg_d[g][NODE_CFG_INIT_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_INIT_SPIN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[INIT_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB]? 
                                                                                                                                      node_cfg_q[NODE_CFG_INIT_SPIN_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB]:
                                                                                                                                      row_node_cfg_q[g][NODE_CFG_INIT_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_INIT_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_cfg_d[g][NODE_CFG_CLAMP_EN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_EN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? 
                                                                                                                                    node_cfg_q[NODE_CFG_CLAMP_EN_PACKED_MSB:NODE_CFG_CLAMP_EN_PACKED_LSB]:
                                                                                                                                    row_node_cfg_q[g][NODE_CFG_CLAMP_EN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_EN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_cfg_d[g][NODE_CFG_CLAMP_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_SPIN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? 
                                                                                                                                        node_cfg_q[NODE_CFG_CLAMP_SPIN_PACKED_MSB:NODE_CFG_CLAMP_SPIN_PACKED_LSB]:
                                                                                                                                        row_node_cfg_q[g][NODE_CFG_CLAMP_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_cfg_d[g][NODE_CFG_BIAS_SIGN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_SIGN_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? 
                                                                                                                                      node_cfg_q[NODE_CFG_BIAS_SIGN_PACKED_MSB:NODE_CFG_BIAS_SIGN_PACKED_LSB]:
                                                                                                                                      row_node_cfg_q[g][NODE_CFG_BIAS_SIGN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_SIGN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_cfg_d[g][NODE_CFG_BIAS_PROB_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_PROB_PACKED_LSB-NODE_CFG_VALID_W] = node_cfg_q[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? 
                                                                                                                                        node_cfg_q[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_BIAS_PROB_PACKED_LSB]:
                                                                                                                                        row_node_cfg_q[g][NODE_CFG_BIAS_PROB_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_PROB_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_cfg_en[g] = node_apply_cfg_pulse_w && (node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_ROW) && (node_target_q[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB] == g);
            assign row_node_seed_d[g] = node_cfg_q[SEED_VALID_PACKED_MSB:SEED_VALID_PACKED_LSB]? 
                                         node_seed_q[NODE_SEED_PACKED_MSB:NODE_SEED_PACKED_LSB]:
                                         row_node_seed_q[g][NODE_SEED_PACKED_MSB:NODE_SEED_PACKED_LSB];
            assign row_node_seed_en[g] = node_apply_cfg_pulse_w && (node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_ROW) && (node_target_q[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB] == g);
            assign row_node_cfg_vld_d[g] = node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_ROW?
                                           node_apply_cfg_pulse_w? 1'b1:
                                           clr_scope_en_pulse_w? 1'b0:
                                           row_node_cfg_vld_q[g]:
                                           row_node_cfg_vld_q[g];  
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Global configuration registers's d port assignment.
    // -------------------------------------------------------------------------
    assign global_cfg_d  =  {reg_wdata_i[NUM_MAJORITY_MSB:NUM_MAJORITY_LSB], reg_wdata_i[NUM_SWEEP_MSB:NUM_SWEEP_LSB]};
    assign global_cfg_en = (reg_addr_i == A_GLOBAL_CFG) && reg_wr_en_i;

    // -------------------------------------------------------------------------
    // SNAPSHOT addr registers's d port assignment.
    // -------------------------------------------------------------------------
    assign snapshot_addr_d = (reg_addr_i == A_SNAPSHOT_ADDR) && reg_wr_en_i ? reg_wdata_i[SNAPSHOT_ADDR_MSB:SNAPSHOT_ADDR_LSB] : snapshot_addr_q;

    // -------------------------------------------------------------------------
    // i0 level registers's d port assignment.
    // -------------------------------------------------------------------------
    assign i0_level_d = {reg_wdata_i[I0_LEVEL3_MSB:I0_LEVEL3_LSB], reg_wdata_i[I0_LEVEL2_MSB:I0_LEVEL2_LSB], reg_wdata_i[I0_LEVEL1_MSB:I0_LEVEL1_LSB], reg_wdata_i[I0_LEVEL0_MSB:I0_LEVEL0_LSB]};
    assign i0_level_en[0] = (reg_addr_i == A_I0_LEVEL0) && reg_wr_en_i;
    assign i0_level_en[1] = (reg_addr_i == A_I0_LEVEL1) && reg_wr_en_i;
    assign i0_level_en[2] = (reg_addr_i == A_I0_LEVEL2) && reg_wr_en_i;
    assign i0_level_en[3] = (reg_addr_i == A_I0_LEVEL3) && reg_wr_en_i;
    assign i0_level_en[4] = (reg_addr_i == A_I0_LEVEL4) && reg_wr_en_i;
    assign i0_level_en[5] = (reg_addr_i == A_I0_LEVEL5) && reg_wr_en_i;
    assign i0_level_en[6] = (reg_addr_i == A_I0_LEVEL6) && reg_wr_en_i;
    assign i0_level_en[7] = (reg_addr_i == A_I0_LEVEL7) && reg_wr_en_i;
    assign i0_level_en[8] = (reg_addr_i == A_I0_LEVEL8) && reg_wr_en_i;
    assign i0_level_en[9] = (reg_addr_i == A_I0_LEVEL9) && reg_wr_en_i;
    assign i0_level_en[10] = (reg_addr_i == A_I0_LEVEL10) && reg_wr_en_i;
    assign i0_level_en[11] = (reg_addr_i == A_I0_LEVEL11) && reg_wr_en_i;
    assign i0_level_en[12] = (reg_addr_i == A_I0_LEVEL12) && reg_wr_en_i;
    assign i0_level_en[13] = (reg_addr_i == A_I0_LEVEL13) && reg_wr_en_i;
    assign i0_level_en[14] = (reg_addr_i == A_I0_LEVEL14) && reg_wr_en_i;
    assign i0_level_en[15] = (reg_addr_i == A_I0_LEVEL15) && reg_wr_en_i;

    // -------------------------------------------------------------------------
    // sweep interval registers's d port assignment.
    // -------------------------------------------------------------------------
    assign sweep_interval_d = {reg_wdata_i[SWEEP_INTERVAL1_MSB:SWEEP_INTERVAL1_LSB], reg_wdata_i[SWEEP_INTERVAL0_MSB:SWEEP_INTERVAL0_LSB]};
    assign sweep_interval_en[0] = (reg_addr_i == A_SWEEP_INTERVAL0) && reg_wr_en_i;
    assign sweep_interval_en[1] = (reg_addr_i == A_SWEEP_INTERVAL1) && reg_wr_en_i;
    assign sweep_interval_en[2] = (reg_addr_i == A_SWEEP_INTERVAL2) && reg_wr_en_i;
    assign sweep_interval_en[3] = (reg_addr_i == A_SWEEP_INTERVAL3) && reg_wr_en_i;
    assign sweep_interval_en[4] = (reg_addr_i == A_SWEEP_INTERVAL4) && reg_wr_en_i;
    assign sweep_interval_en[5] = (reg_addr_i == A_SWEEP_INTERVAL5) && reg_wr_en_i;
    assign sweep_interval_en[6] = (reg_addr_i == A_SWEEP_INTERVAL6) && reg_wr_en_i;
    assign sweep_interval_en[7] = (reg_addr_i == A_SWEEP_INTERVAL7) && reg_wr_en_i;
    assign sweep_interval_en[8] = (reg_addr_i == A_SWEEP_INTERVAL8) && reg_wr_en_i;
    assign sweep_interval_en[9] = (reg_addr_i == A_SWEEP_INTERVAL9) && reg_wr_en_i;
    assign sweep_interval_en[10] = (reg_addr_i == A_SWEEP_INTERVAL10) && reg_wr_en_i;
    assign sweep_interval_en[11] = (reg_addr_i == A_SWEEP_INTERVAL11) && reg_wr_en_i;
    assign sweep_interval_en[12] = (reg_addr_i == A_SWEEP_INTERVAL12) && reg_wr_en_i;
    assign sweep_interval_en[13] = (reg_addr_i == A_SWEEP_INTERVAL13) && reg_wr_en_i;
    assign sweep_interval_en[14] = (reg_addr_i == A_SWEEP_INTERVAL14) && reg_wr_en_i;
    assign sweep_interval_en[15] = (reg_addr_i == A_SWEEP_INTERVAL15) && reg_wr_en_i;
    assign sweep_interval_en[16] = (reg_addr_i == A_SWEEP_INTERVAL16) && reg_wr_en_i;
    assign sweep_interval_en[17] = (reg_addr_i == A_SWEEP_INTERVAL17) && reg_wr_en_i;
    assign sweep_interval_en[18] = (reg_addr_i == A_SWEEP_INTERVAL18) && reg_wr_en_i;
    assign sweep_interval_en[19] = (reg_addr_i == A_SWEEP_INTERVAL19) && reg_wr_en_i;
    assign sweep_interval_en[20] = (reg_addr_i == A_SWEEP_INTERVAL20) && reg_wr_en_i;
    assign sweep_interval_en[21] = (reg_addr_i == A_SWEEP_INTERVAL21) && reg_wr_en_i;
    assign sweep_interval_en[22] = (reg_addr_i == A_SWEEP_INTERVAL22) && reg_wr_en_i;
    assign sweep_interval_en[23] = (reg_addr_i == A_SWEEP_INTERVAL23) && reg_wr_en_i;
    assign sweep_interval_en[24] = (reg_addr_i == A_SWEEP_INTERVAL24) && reg_wr_en_i;
    assign sweep_interval_en[25] = (reg_addr_i == A_SWEEP_INTERVAL25) && reg_wr_en_i;
    assign sweep_interval_en[26] = (reg_addr_i == A_SWEEP_INTERVAL26) && reg_wr_en_i;
    assign sweep_interval_en[27] = (reg_addr_i == A_SWEEP_INTERVAL27) && reg_wr_en_i;
    assign sweep_interval_en[28] = (reg_addr_i == A_SWEEP_INTERVAL28) && reg_wr_en_i;
    assign sweep_interval_en[29] = (reg_addr_i == A_SWEEP_INTERVAL29) && reg_wr_en_i;
    assign sweep_interval_en[30] = (reg_addr_i == A_SWEEP_INTERVAL30) && reg_wr_en_i;
    assign sweep_interval_en[31] = (reg_addr_i == A_SWEEP_INTERVAL31) && reg_wr_en_i;

    // -------------------------------------------------------------------------
    // ERROR_STATUS registers's d port assignment.
    // -------------------------------------------------------------------------
    logic addr_valid_w;
    logic addr_writable_w;
    logic addr_readable_w;
    logic node_target_mode_valid_w;
    logic node_target_row_valid_w;
    logic node_target_col_valid_w;
    logic edge_target_type_valid_w;
    logic edge_target_row_valid_w;
    logic edge_target_col_valid_w;
    assign addr_valid_w = addr_valid(reg_addr_i);
    assign addr_writable_w = addr_writable(reg_addr_i);
    assign addr_readable_w = addr_readable(reg_addr_i);
    assign node_target_mode_valid_w = node_target_mode_valid(node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB]);
    assign node_target_row_valid_w = node_target_row_valid(node_target_q[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB]);
    assign node_target_col_valid_w = node_target_col_valid(node_target_q[NODE_TARGET_COL_PACKED_MSB:NODE_TARGET_COL_PACKED_LSB]);
    assign edge_target_type_valid_w = edge_target_type_valid(cfg_edge_type_q[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB]);
    assign edge_target_row_valid_w = edge_target_row_valid(cfg_edge_type_q, cfg_edge_row_q);
    assign edge_target_col_valid_w = edge_target_col_valid(cfg_edge_type_q, cfg_edge_col_q);
    assign error_status_d[ADDR_ERR_PACKED_MSB:ADDR_ERR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                     ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[ADDR_ERR_MSB:ADDR_ERR_LSB] && reg_wr_en_i)? 1'b0:
                                                                     (reg_wr_en_i || reg_rd_en_i)? !addr_valid_w: 
                                                                     error_status_q[ADDR_ERR_PACKED_MSB:ADDR_ERR_PACKED_LSB];
    assign error_status_d[WR_TO_RO_PACKED_MSB:WR_TO_RO_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                     ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[WR_TO_RO_MSB:WR_TO_RO_LSB] && reg_wr_en_i)? 1'b0: 
                                                                     (reg_wr_en_i)? addr_valid_w && (!addr_writable_w):
                                                                     error_status_q[WR_TO_RO_PACKED_MSB:WR_TO_RO_PACKED_LSB];
    assign error_status_d[RD_TO_WO_PACKED_MSB:RD_TO_WO_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                     ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[RD_TO_WO_MSB:RD_TO_WO_LSB] && reg_wr_en_i)? 1'b0: 
                                                                     (reg_rd_en_i)? addr_valid_w && (!addr_readable_w):
                                                                     error_status_q[RD_TO_WO_PACKED_MSB:RD_TO_WO_PACKED_LSB];
    assign error_status_d[NODE_CFG_WHILE_RUN_PACKED_MSB:NODE_CFG_WHILE_RUN_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                                         ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[NODE_CFG_WHILE_RUN_MSB:NODE_CFG_WHILE_RUN_LSB] && reg_wr_en_i)? 1'b0: 
                                                                                         (run_busy_w && ((reg_addr_i == A_NODE_CMD) && reg_wr_en_i))? 1'b1:
                                                                                         error_status_q[NODE_CFG_WHILE_RUN_PACKED_MSB:NODE_CFG_WHILE_RUN_PACKED_LSB];
    assign error_status_d[EDGE_CFG_WHILE_RUN_PACKED_MSB:EDGE_CFG_WHILE_RUN_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                                         ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[EDGE_CFG_WHILE_RUN_MSB:EDGE_CFG_WHILE_RUN_LSB] && reg_wr_en_i)? 1'b0: 
                                                                                         (run_busy_w && ((reg_addr_i == A_EDGE_CMD) && reg_wr_en_i))? 1'b1:
                                                                                         error_status_q[EDGE_CFG_WHILE_RUN_PACKED_MSB:EDGE_CFG_WHILE_RUN_PACKED_LSB];
    assign error_status_d[RUN_WITHOUT_CFG_DONE_PACKED_MSB:RUN_WITHOUT_CFG_DONE_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                                             ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[RUN_WITHOUT_CFG_DONE_MSB:RUN_WITHOUT_CFG_DONE_LSB] && reg_wr_en_i)? 1'b0: 
                                                                                             (!cfg_done_q && run_start_pulse_w)? 1'b1:
                                                                                             error_status_q[RUN_WITHOUT_CFG_DONE_PACKED_MSB:RUN_WITHOUT_CFG_DONE_PACKED_LSB];
    assign error_status_d[RUN_WHEN_BUSY_PACKED_MSB:RUN_WHEN_BUSY_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                               ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[RUN_WHEN_BUSY_MSB:RUN_WHEN_BUSY_LSB] && reg_wr_en_i)? 1'b0: 
                                                                               (run_busy_w && run_start_pulse_w)? 1'b1:
                                                                               error_status_q[RUN_WHEN_BUSY_PACKED_MSB:RUN_WHEN_BUSY_PACKED_LSB];      
    assign error_status_d[NODE_TARGET_MODE_ERR_PACKED_MSB:NODE_TARGET_MODE_ERR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                                             ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[NODE_TARGET_MODE_ERR_MSB:NODE_TARGET_MODE_ERR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                                             ((node_apply_cfg_pulse_w || local_node_cfg_pulse_w || clr_scope_en_pulse_w || local_node_clr_pulse_w || node_rdata_pulse_w) && !node_target_mode_valid_w)? 1'b1:
                                                                                             error_status_q[NODE_TARGET_MODE_ERR_PACKED_MSB:NODE_TARGET_MODE_ERR_PACKED_LSB];   
    assign error_status_d[NODE_ROW_OOR_PACKED_MSB:NODE_ROW_OOR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                             ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[NODE_ROW_OOR_MSB:NODE_ROW_OOR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                             ((node_apply_cfg_pulse_w || local_node_cfg_pulse_w || clr_scope_en_pulse_w || local_node_clr_pulse_w || node_rdata_pulse_w) && !node_target_row_valid_w)? 1'b1:
                                                                             error_status_q[NODE_ROW_OOR_PACKED_MSB:NODE_ROW_OOR_PACKED_LSB]; 
    assign error_status_d[NODE_COL_OOR_PACKED_MSB:NODE_COL_OOR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                             ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[NODE_COL_OOR_MSB:NODE_COL_OOR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                             ((node_apply_cfg_pulse_w || local_node_cfg_pulse_w || clr_scope_en_pulse_w || local_node_clr_pulse_w || node_rdata_pulse_w) && !node_target_col_valid_w)? 1'b1:
                                                                             error_status_q[NODE_ROW_OOR_PACKED_MSB:NODE_ROW_OOR_PACKED_LSB];  
    assign error_status_d[EDGE_ROW_OOR_PACKED_MSB:EDGE_ROW_OOR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                             ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[EDGE_ROW_OOR_MSB:EDGE_ROW_OOR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                             ((edge_apply_cfg_pulse_w || cfg_edge_clr_pulse_w || edge_rdata_pulse_w) && !edge_target_row_valid_w)? 1'b1:
                                                                             error_status_q[EDGE_ROW_OOR_PACKED_MSB:EDGE_ROW_OOR_PACKED_LSB]; 
    assign error_status_d[EDGE_COL_OOR_PACKED_MSB:EDGE_COL_OOR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                             ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[EDGE_COL_OOR_MSB:EDGE_COL_OOR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                             ((edge_apply_cfg_pulse_w || cfg_edge_clr_pulse_w || edge_rdata_pulse_w) && !edge_target_col_valid_w)? 1'b1:
                                                                             error_status_q[EDGE_COL_OOR_PACKED_MSB:EDGE_COL_OOR_PACKED_LSB];
    assign error_status_d[EDGE_TYPE_ERR_PACKED_MSB:EDGE_TYPE_ERR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                               ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[EDGE_TYPE_ERR_MSB:EDGE_TYPE_ERR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                               ((edge_apply_cfg_pulse_w || cfg_edge_clr_pulse_w || edge_rdata_pulse_w) && !edge_target_type_valid_w)? 1'b1:
                                                                               error_status_q[EDGE_TYPE_ERR_PACKED_MSB:EDGE_TYPE_ERR_PACKED_LSB];                                                                                                                                                                                                                                                        
    assign error_status_d[UART_FRAME_ERR_PACKED_MSB:UART_FRAME_ERR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                                 ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[UART_FRAME_ERR_MSB:UART_FRAME_ERR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                                 uart_frame_err_pulse_w? 1'b1:
                                                                                 error_status_q[UART_FRAME_ERR_PACKED_MSB:UART_FRAME_ERR_PACKED_LSB];    
    assign error_status_d[UART_OVERFLOW_PACKED_MSB:UART_OVERFLOW_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                               ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[UART_OVERFLOW_MSB:UART_OVERFLOW_LSB] && reg_wr_en_i)? 1'b0: 
                                                                               uart_overflow_pulse_w? 1'b1:
                                                                               error_status_q[UART_OVERFLOW_PACKED_MSB:UART_OVERFLOW_PACKED_LSB];    
    assign error_status_d[SNAP_ADDR_OOR_PACKED_MSB:SNAP_ADDR_OOR_PACKED_LSB] = error_clear_pulse_w ? 1'b0 :
                                                                               ((reg_addr_i == A_ERROR_STATUS) && reg_wdata_i[SNAP_ADDR_OOR_MSB:SNAP_ADDR_OOR_LSB] && reg_wr_en_i)? 1'b0: 
                                                                               (snapshot_latch_pulse_w && (snapshot_addr_q[SNAPSHOT_ADDR_PACKED_MSB:SNAPSHOT_ADDR_PACKED_LSB] < SPIN_ADDR_MAX[SNAPSHOT_ADDR_WIDTH-1:0]))? 1'b1:
                                                                               error_status_q[SNAP_ADDR_OOR_PACKED_MSB:SNAP_ADDR_OOR_PACKED_LSB];    
    
    // -------------------------------------------------------------------------
    // Global status registers
    // -------------------------------------------------------------------------
    assign cfg_done_d = cfg_done_set_pulse_w ? 1'b1 : cfg_done_clr_pulse_w ? 1'b0: cfg_done_q;
    assign node_cfg_done_d = ((reg_addr_i == A_GLOBAL_STATUS) && reg_rd_en_i)? 1'b0:
                             (node_apply_cfg_pulse_w || local_node_cfg_pulse_w || node_load_pulse_w || clr_scope_en_pulse_w ||
                              local_node_clr_pulse_w || clr_local_all_pulse_w || node_rdata_pulse_w)? 1'b1:
                              node_cfg_done_q;
    assign edge_cfg_done_d = ((reg_addr_i == A_GLOBAL_STATUS) && reg_rd_en_i)? 1'b0:
                             (edge_apply_cfg_pulse_w || cfg_edge_clr_pulse_w || edge_rdata_pulse_w)? 1'b1:
                              edge_cfg_done_q; 
    // ----------------------------------------------------------
    // Glboal Control registers's assignment.
    // -------------------------------------------------------------------------
    assign glb_soft_rstn_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (!reg_wdata_i[SOFT_RESET_MSB:SOFT_RESET_LSB]);
    assign cfg_done_set_pulse_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (reg_wdata_i[CFG_DONE_SET_MSB:CFG_DONE_SET_LSB]) && !run_busy_w;
    assign cfg_done_clr_pulse_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (reg_wdata_i[CFG_DONE_CLEAR_MSB:CFG_DONE_CLEAR_LSB]) && !run_busy_w;
    assign run_start_pulse_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (reg_wdata_i[RUN_START_MSB:RUN_START_LSB]) && !run_busy_w && cfg_done_q;
    assign snapshot_latch_pulse_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (reg_wdata_i[SNAPSHOT_LATCH_MSB:SNAPSHOT_LATCH_LSB]) && !run_busy_w && snapshot_addr_valid(snapshot_addr_q);
    assign run_done_clr_pulse_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (reg_wdata_i[RUN_DONE_CLEAR_MSB:RUN_DONE_CLEAR_LSB]) && !run_busy_w;
    assign error_clear_pulse_w = (reg_addr_i == A_GLOBAL_CTRL) && reg_wr_en_i && (reg_wdata_i[ERROR_CLEAR_MSB:ERROR_CLEAR_LSB]);

    // -------------------------------------------------------------------------
    // Node Control registers's assignment.
    // -------------------------------------------------------------------------
    assign node_apply_cfg_pulse_w = (reg_addr_i == A_NODE_CMD) && reg_wr_en_i && (reg_wdata_i[APPLY_CFG_MSB:APPLY_CFG_LSB]) && !run_busy_w;
    assign local_node_cfg_pulse_w = node_apply_cfg_pulse_w && (node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_LOCAL) && !run_busy_w;
    assign node_load_pulse_w = (reg_addr_i == A_NODE_CMD) && reg_wr_en_i && (reg_wdata_i[LOAD_CFG_MSB:LOAD_CFG_LSB]) && !run_busy_w;
    assign clr_scope_en_pulse_w = (reg_addr_i == A_NODE_CMD) && reg_wr_en_i && (reg_wdata_i[CLEAR_SCOPE_EN_MSB:CLEAR_SCOPE_EN_LSB]) && !run_busy_w;
    assign local_node_clr_pulse_w = clr_scope_en_pulse_w && (node_target_q[TARGET_MODE_PACKED_MSB:TARGET_MODE_PACKED_LSB] == TARGET_MODE_LOCAL);
    assign clr_local_all_pulse_w = (reg_addr_i == A_NODE_CMD) && reg_wr_en_i && (reg_wdata_i[CLEAR_LOCAL_ALL_MSB:CLEAR_LOCAL_ALL_LSB]) && !run_busy_w;
    assign node_rdata_pulse_w = (reg_addr_i == A_NODE_CMD) && reg_wr_en_i && (reg_wdata_i[READBACK_NODE_MSB:READBACK_NODE_LSB]) && !run_busy_w;

    // -------------------------------------------------------------------------
    // Edge Control registers's assignment.
    // -------------------------------------------------------------------------
    assign edge_apply_cfg_pulse_w = (reg_addr_i == A_EDGE_CMD) && reg_wr_en_i && (reg_wdata_i[APPLY_EDGE_MSB:APPLY_EDGE_LSB]) && !run_busy_w;
    assign cfg_edge_clr_pulse_w = (reg_addr_i == A_EDGE_CMD) && reg_wr_en_i && (reg_wdata_i[CLEAR_EDGE_MSB:CLEAR_EDGE_LSB]) && !run_busy_w;
    assign edge_rdata_pulse_w = (reg_addr_i == A_EDGE_CMD) && reg_wr_en_i && (reg_wdata_i[READBACK_EDGE_MSB:READBACK_EDGE_LSB]) && !run_busy_w;

    // -------------------------------------------------------------------------
    // Register read mux register instantiation.
    // -------------------------------------------------------------------------
    dffe #(.WIDTH(32)
    ) reg_rdata_ff(
        .clk(clk),
        .en_i(reg_rdata_en),
        .d_i(reg_rdata_d),
        .q_o(reg_rdata_q)
    );

    // -------------------------------------------------------------------------
    // Node staging registers instantiation.
    // -------------------------------------------------------------------------
    dffe #(.WIDTH(NODE_TARGET_PACKED_WIDTH)
    ) node_target_ff(
        .clk (clk),
        .en_i(node_target_en),
        .d_i (node_target_d),
        .q_o (node_target_q)
    );

    dffe #(.WIDTH(NODE_CFG_PACKED_WIDTH)
    ) node_cfg_ff(
        .clk (clk),
        .en_i(node_cfg_en),
        .d_i (node_cfg_d),
        .q_o (node_cfg_q)
    );

    dffe #(.WIDTH(NODE_SEED_PACKED_WIDTH)
    ) node_seed_ff(
        .clk (clk),
        .en_i(node_seed_en),
        .d_i (node_seed_d),
        .q_o (node_seed_q)
    );

    // -------------------------------------------------------------------------
    // Edge staging registers instantiation.
    // -------------------------------------------------------------------------
    dff #(.WIDTH(EDGE_TYPE_WIDTH)
    ) cfg_edge_type_ff(
        .clk (clk),
        .d_i (cfg_edge_type_d),
        .q_o (cfg_edge_type_q)
    );

    dffe #(.WIDTH(EDGE_TARGET_ROW_WIDTH)
    ) cfg_edge_row_ff(
        .clk (clk),
        .en_i(cfg_edge_row_en),
        .d_i (cfg_edge_row_d),
        .q_o (cfg_edge_row_q)
    );

    dffe #(.WIDTH(EDGE_TARGET_COL_WIDTH)
    ) cfg_edge_col_ff(
        .clk (clk),
        .en_i(cfg_edge_col_en),
        .d_i (cfg_edge_col_d),
        .q_o (cfg_edge_col_q)
    );

    dffe #(.WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) cfg_edge_prob_ff(
        .clk (clk),
        .en_i(cfg_edge_prob_en),
        .d_i (cfg_edge_prob_d),
        .q_o (cfg_edge_prob_q)
    );

    dff #(.WIDTH(EDGE_CFG_EDGE_SIGN_WIDTH)
    ) cfg_edge_sign_ff(
        .clk (clk),
        .d_i (cfg_edge_sign_d),
        .q_o (cfg_edge_sign_q)
    );

    dff #(.WIDTH(EDGE_CFG_EDGE_VALID_WIDTH)
    ) cfg_edge_valid_ff(
        .clk (clk),
        .d_i (cfg_edge_valid_d),
        .q_o (cfg_edge_valid_q)
    );

    // -------------------------------------------------------------------------
    // Backend node configuration registers instantiation.
    // -------------------------------------------------------------------------
    dffe #(.WIDTH(NODE_CFG_W)
    ) global_node_cfg_ff(
        .clk (clk),
        .en_i(global_node_cfg_en),
        .d_i (global_node_cfg_d),
        .q_o (global_node_cfg_q)
    );

    dffe #(.WIDTH(NODE_SEED_WIDTH)
    ) global_node_seed_ff(
        .clk (clk),
        .en_i(global_node_seed_en),
        .d_i (global_node_seed_d),
        .q_o (global_node_seed_q)
    );

    dffr #(.WIDTH(1)
    ) global_node_cfg_vld_ff(
        .clk (clk),
        .rst_n (rst_n),
        .d_i (global_node_cfg_vld_d),
        .q_o (global_node_cfg_vld_q)
    );

    generate
        for(g = 0; g < ROWS; g = g + 1) begin : ROW_NODE_CFG_FF
            dffe #(.WIDTH(NODE_CFG_W)
            ) row_node_cfg_ff(
                .clk (clk),
                .en_i(row_node_cfg_en[g]),
                .d_i (row_node_cfg_d[g]),
                .q_o (row_node_cfg_q[g])
            );

            dffe #(.WIDTH(NODE_SEED_WIDTH)
            ) row_node_seed_ff(
                .clk (clk),
                .en_i(row_node_seed_en[g]),
                .d_i (row_node_seed_d[g]),
                .q_o (row_node_seed_q[g])
            );

            dffr #(.WIDTH(1)
            ) row_node_cfg_vld_ff(
                .clk (clk),
                .rst_n (rst_n),
                .d_i (row_node_cfg_vld_d[g]),
                .q_o (row_node_cfg_vld_q[g])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Global configuration registers instantiation.
    // -------------------------------------------------------------------------
    dffe #(.WIDTH(GLOBAL_CFG_PACKED_WIDTH)
    ) global_cfg_ff(
        .clk (clk),
        .en_i(global_cfg_en),
        .d_i (global_cfg_d),
        .q_o (global_cfg_q)
    );

    // -------------------------------------------------------------------------
    // SNAPSHOT addr registers instantiation.
    // -------------------------------------------------------------------------
    dff #(.WIDTH(SNAPSHOT_ADDR_PACKED_WIDTH)
    ) snapshot_addr_ff(
        .clk (clk),
        .d_i (snapshot_addr_d),
        .q_o (snapshot_addr_q)
    );

    // -------------------------------------------------------------------------
    // i0 level registers instantiation.
    // -------------------------------------------------------------------------
    generate
        for(g = 0; g < I0_LEVEL_REG_NUM; g = g + 1) begin :I0_LEVEL_REG_INST 
            dffe #(.WIDTH(I0_LEVEL_PACKED_WIDTH)
            ) i0_level_ff(
                .clk(clk),
                .en_i(i0_level_en[g]),
                .d_i(i0_level_d),
                .q_o(i0_level_q[g])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // SWEEP interval registers instantiation.
    // -------------------------------------------------------------------------
    generate
        for(g = 0; g < SWEEP_INTERVAL_REG_NUM; g = g + 1) begin :SWEEP_INTERVAL_REG_INST 
            dffe #(.WIDTH(SWEEP_INTERVAL_PACKED_WIDTH)
            ) sweep_interval_ff(
                .clk(clk),
                .en_i(sweep_interval_en[g]),
                .d_i(sweep_interval_d),
                .q_o(sweep_interval_q[g])
            );
        end
    endgenerate
    // -------------------------------------------------------------------------
    // ERROR_STATUS registers instantiation.
    // -------------------------------------------------------------------------
    dffr #(.WIDTH(ERROR_STATUS_PACKED_WIDTH)
    ) error_status_ff(
        .clk (clk),
        .rst_n (rst_n),
        .d_i (error_status_d),
        .q_o (error_status_q)
    );

    // -------------------------------------------------------------------------
    // Global status registers instantiation.
    // -------------------------------------------------------------------------
    dffr #(.WIDTH(1)
    ) cfg_done_ff(
        .clk (clk),
        .rst_n (rst_n),
        .d_i (cfg_done_d),
        .q_o (cfg_done_q)
    );
    
    dffr #(.WIDTH(1)
    ) node_cfg_done_ff(
        .clk (clk),
        .rst_n (rst_n),
        .d_i (node_cfg_done_d),
        .q_o (node_cfg_done_q)
    );

    dffr #(.WIDTH(1)
    ) edge_cfg_done_ff(
        .clk (clk),
        .rst_n (rst_n),
        .d_i (edge_cfg_done_d),
        .q_o (edge_cfg_done_q)
    );
endmodule
`endif