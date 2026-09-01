`ifndef PBIT_ARRAY_KINGS
`define PBIT_ARRAY_KINGS
import pbit_pkg::*;
module pbit_array_kings (
    input  logic clk,
    input  logic rst_n,
    // ------------------------------------------------------------
    // Four phase-start enables.
    // Single clock, four phase enables, not four clocks.
    // ------------------------------------------------------------
    input  logic                                 phase_start_c0_i,
    input  logic                                 phase_start_c1_i,
    input  logic                                 phase_start_c2_i,
    input  logic                                 phase_start_c3_i,

    input  logic [I0_LEVEL_WIDTH-1:0]            i0_level_i,

    // ------------------------------------------------------------
    // Snapshot Readback.
    // ------------------------------------------------------------
    input  logic [SNAPSHOT_ADDR_WIDTH-1:0]       snapshot_addr_i,
    input  logic                                 snapshot_latch_pulse_i,
    output logic [SNAPSHOT_WIDTH-1:0]            snapshot_flat_o,
    output logic                                 snapshot_vld_o,

    // ------------------------------------------------------------
    // Global control
    // ------------------------------------------------------------
    input  logic                                 glb_soft_rstn_i,
    input  logic [NUM_MAJORITY_WIDTH-1:0]        num_majority_i,
    // ------------------------------------------------------------
    // Node configuration.
    // ------------------------------------------------------------
    input  logic [NODE_CFG_W-1:0]                global_node_cfg_i,
    input  logic [NODE_SEED_WIDTH-1:0]           global_node_seed_i,
    input  logic                                 global_node_cfg_vld_i,
    input  logic                                 global_node_seed_vld_i,

    input  wire  [NODE_CFG_W-1:0]                row_node_cfg_i[0:ROWS-1],
    input  wire  [NODE_SEED_WIDTH-1:0]           row_node_seed_i[0:SEED_ROWS-1],
    input  logic [ROWS-1:0]                      row_node_cfg_vld_i,
    input  logic [SEED_ROWS-1:0]                 row_node_seed_vld_i,

    input  logic                                 local_node_cfg_we_pulse_i,
    input  logic                                 local_node_cfg_clr_pulse_i,
    input  logic                                 local_node_seed_we_pulse_i,
    input  logic                                 local_node_seed_clr_pulse_i,
    input  logic [NODE_TARGET_ROW_WIDTH-1:0]     node_row_i,
    input  logic [NODE_TARGET_COL_WIDTH-1:0]     node_col_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]     local_node_cfg_i,
    input  logic [NODE_SEED_WIDTH-1:0]           local_node_seed_i,
    input  logic                                 clr_local_all_pulse_i,
  
    input  logic                                 node_load_pulse_i,
    // ------------------------------------------------------------
    // Edge configuration.
    // One edge write per cycle.
    //
    // edge_type:
    // 0 = H   : (r,c) -- (r,c+1)
    // 1 = V   : (r,c) -- (r+1,c)
    // 2 = DSE : (r,c) -- (r+1,c+1)
    // 3 = DSW : (r,c) -- (r+1,c-1)
    // ------------------------------------------------------------
    input  logic                                 cfg_edge_we_pulse_i,
    input  logic                                 cfg_edge_clr_pulse_i,
    input  logic [EDGE_TYPE_WIDTH-1:0]           cfg_edge_type_i,
    input  logic [EDGE_TARGET_ROW_WIDTH-1:0]     cfg_edge_row_i,
    input  logic [EDGE_TARGET_COL_WIDTH-1:0]     cfg_edge_col_i,
    input  logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  cfg_edge_prob_i,
    input  logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]  cfg_edge_sign_i,
    input  logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] cfg_edge_valid_i,

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    output logic all_done_c0_o,
    output logic all_done_c1_o,
    output logic all_done_c2_o,
    output logic all_done_c3_o
);

    genvar r;
    genvar c;
    // ------------------------------------------------------------
    // Snapshot Readback.
    // ------------------------------------------------------------
    logic [SNAPSHOT_WIDTH-1:0] snapshot_flat_q, snapshot_flat_d;
    logic snapshot_flat_en;
    logic snapshot_vld_q, snapshot_vld_d;

    assign snapshot_flat_o = snapshot_flat_q;
    assign snapshot_vld_o = snapshot_vld_q;
    // ------------------------------------------------------------
    // Node configuration decode
    // ------------------------------------------------------------
    logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  global_node_init_spin_w;
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   global_node_clamp_en_w;
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] global_node_clamp_spin_w;
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  global_node_bias_sign_w;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  global_node_bias_prob_w;
    logic [NODE_SEED_WIDTH-1:0]           global_node_seed_w;

    logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  row_node_init_spin_w[ROWS];
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   row_node_clamp_en_w[ROWS];
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] row_node_clamp_spin_w[ROWS];
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  row_node_bias_sign_w[ROWS];
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  row_node_bias_prob_w[ROWS];
    logic [NODE_SEED_WIDTH-1:0]           row_node_seed_w[SEED_ROWS];

    logic [NODE_SEED_WIDTH-1:0]           local_node_seed_w;

    assign global_node_init_spin_w  = global_node_cfg_i[NODE_CFG_INIT_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_INIT_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_clamp_en_w   = global_node_cfg_i[NODE_CFG_CLAMP_EN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_EN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_clamp_spin_w = global_node_cfg_i[NODE_CFG_CLAMP_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_bias_sign_w  = global_node_cfg_i[NODE_CFG_BIAS_SIGN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_SIGN_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_bias_prob_w  = global_node_cfg_i[NODE_CFG_BIAS_PROB_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_PROB_PACKED_LSB-NODE_CFG_VALID_W];
    assign global_node_seed_w       = global_node_seed_i;

    generate
        for(r = 0; r < ROWS; r++) begin: ROW_NODE_CFG_DECODE
            assign row_node_init_spin_w[r]  = row_node_cfg_i[r][NODE_CFG_INIT_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_INIT_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_clamp_en_w[r]   = row_node_cfg_i[r][NODE_CFG_CLAMP_EN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_EN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_clamp_spin_w[r] = row_node_cfg_i[r][NODE_CFG_CLAMP_SPIN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_CLAMP_SPIN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_bias_sign_w[r]  = row_node_cfg_i[r][NODE_CFG_BIAS_SIGN_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_SIGN_PACKED_LSB-NODE_CFG_VALID_W];
            assign row_node_bias_prob_w[r]  = row_node_cfg_i[r][NODE_CFG_BIAS_PROB_PACKED_MSB-NODE_CFG_VALID_W:NODE_CFG_BIAS_PROB_PACKED_LSB-NODE_CFG_VALID_W];
        end
        
        for(r = 0; r < SEED_ROWS; r++) begin: ROW_NODE_SEED_DECODE
            assign row_node_seed_w[r]       = row_node_seed_i[r];
        end
    endgenerate

    assign local_node_seed_w       = local_node_seed_i;

    // ------------------------------------------------------------
    // Node spin and done arrays
    // ------------------------------------------------------------
    logic spin [ROWS][COLS];
    logic [N_SPIN-1:0] spin_flat;
    logic [SNAPSHOT_WIDTH-1:0] spin_flat_reshape[SPIN_ADDR_MAX];

    // ------------------------------------------------------------
    // Directional wires into each p-bit
    // ------------------------------------------------------------
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_n  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_ne [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_e  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_se [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_s  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_sw [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_w  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_nw [0:ROWS-1][0:COLS-1];

    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_n  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_ne [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_e  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_se [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_s  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_sw [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_w  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_nw [0:ROWS-1][0:COLS-1];

    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_n  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_ne [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_e  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_se [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_s  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_sw [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_w  [0:ROWS-1][0:COLS-1];
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] sign_nw [0:ROWS-1][0:COLS-1];

    logic nbr_n  [0:ROWS-1][0:COLS-1];
    logic nbr_ne [0:ROWS-1][0:COLS-1];
    logic nbr_e  [0:ROWS-1][0:COLS-1];
    logic nbr_se [0:ROWS-1][0:COLS-1];
    logic nbr_s  [0:ROWS-1][0:COLS-1];
    logic nbr_sw [0:ROWS-1][0:COLS-1];
    logic nbr_w  [0:ROWS-1][0:COLS-1];
    logic nbr_nw [0:ROWS-1][0:COLS-1];

    // ------------------------------------------------------------
    // lfsr32_rng32
    // ------------------------------------------------------------
    logic lfsr_en_w;
    logic [NODE_SEED_WIDTH-1:0] lfsr_rnd_32_w[0:SEED_ROWS-1][0:SEED_COLS-1];

    // ------------------------------------------------------------
    // tanh LUT wires
    // ------------------------------------------------------------
    logic signed [MACSUM_WIDTH-1:0] macsum_w[0:ROWS-1][0:COLS-1];
    logic [3:0]                     tanh_sel_w;
    logic [LUT_WIDTH-1:0]           p_up_thr_w[0:TANH_ROWS-1][0:TANH_COLS-1];
    // ------------------------------------------------------------
    // Done signal counter
    // 2*num_majority+2
    // ------------------------------------------------------------
    logic done_c0_q, done_c0_d;
    logic done_c1_q, done_c1_d;
    logic done_c2_q, done_c2_d;
    logic done_c3_q, done_c3_d;

    logic is_c0_q, is_c0_d;
    logic is_c1_q, is_c1_d;
    logic is_c2_q, is_c2_d;
    logic is_c3_q, is_c3_d;

    logic [NUM_MAJORITY_WIDTH+1:0] done_c0_cnt_q, done_c0_cnt_d;
    logic done_c0_cnt_en;
    logic [NUM_MAJORITY_WIDTH+1:0] done_c1_cnt_q, done_c1_cnt_d;
    logic done_c1_cnt_en;
    logic [NUM_MAJORITY_WIDTH+1:0] done_c2_cnt_q, done_c2_cnt_d;
    logic done_c2_cnt_en;
    logic [NUM_MAJORITY_WIDTH+1:0] done_c3_cnt_q, done_c3_cnt_d;
    logic done_c3_cnt_en;
    logic [NUM_MAJORITY_WIDTH+1:0] cnt_max;

    assign all_done_c0_o = done_c0_q;
    assign all_done_c1_o = done_c1_q;
    assign all_done_c2_o = done_c2_q;
    assign all_done_c3_o = done_c3_q;
    // ------------------------------------------------------------
    // Boundary defaults.
    // These directions have no edge coupler driving them.
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_BOUND_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_BOUND_C

                if (r == 0) begin : N
                    assign prob_n[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_n[r][c]  = 1'b1;
                    assign valid_n[r][c] = 1'b0;
                    assign nbr_n[r][c]   = 1'b0;
                end

                if (r == ROWS-1) begin : S
                    assign prob_s[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_s[r][c]  = 1'b1;
                    assign valid_s[r][c] = 1'b0;
                    assign nbr_s[r][c]   = 1'b0;
                end

                if (c == 0) begin : W
                    assign prob_w[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_w[r][c]  = 1'b1;
                    assign valid_w[r][c] = 1'b0;
                    assign nbr_w[r][c]   = 1'b0;
                end

                if (c == COLS-1) begin : E
                    assign prob_e[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_e[r][c]  = 1'b1;
                    assign valid_e[r][c] = 1'b0;
                    assign nbr_e[r][c]   = 1'b0;
                end

                if ((r == 0) || (c == COLS-1)) begin : NE
                    assign prob_ne[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_ne[r][c]  = 1'b1;
                    assign valid_ne[r][c] = 1'b0;
                    assign nbr_ne[r][c]   = 1'b0;
                end

                if ((r == 0) || (c == 0)) begin : NW
                    assign prob_nw[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_nw[r][c]  = 1'b1;
                    assign valid_nw[r][c] = 1'b0;
                    assign nbr_nw[r][c]   = 1'b0;
                end

                if ((r == ROWS-1) || (c == COLS-1)) begin : SE
                    assign prob_se[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_se[r][c]  = 1'b1;
                    assign valid_se[r][c] = 1'b0;
                    assign nbr_se[r][c]   = 1'b0;
                end

                if ((r == ROWS-1) || (c == 0)) begin : SW
                    assign prob_sw[r][c]  = {EDGE_CFG_EDGE_PROB_WIDTH{1'b0}};
                    assign sign_sw[r][c]  = 1'b1;
                    assign valid_sw[r][c] = 1'b0;
                    assign nbr_sw[r][c]   = 1'b0;
                end

            end
        end
    endgenerate
    // ------------------------------------------------------------
    // Instantiate all p-bit nodes.
    // Compile-time color:
    // color = 2*(row%2) + (col%2)
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_NODE_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_NODE_C

                localparam integer CELL_COLOR = (r % 2) * 2 + (c % 2);

                logic local_start_w;
                logic local_node_cfg_we_match_w;
                logic local_node_cfg_clr_pulse_match_w;
                // Shared LUT output is a full probability threshold; keep all bits for pbit_node compare.
                logic [LUT_WIDTH-1:0] p_up_thr_match_w;
                logic [31:0] lfsr_rnd_32_match_w;
                assign local_start_w =
                    (CELL_COLOR == 0) ? phase_start_c0_i :
                    (CELL_COLOR == 1) ? phase_start_c1_i :
                    (CELL_COLOR == 2) ? phase_start_c2_i :
                                        phase_start_c3_i;

                assign local_node_cfg_we_match_w =
                    local_node_cfg_we_pulse_i &&
                    (node_row_i == r[NODE_TARGET_ROW_WIDTH-1:0]) &&
                    (node_col_i == c[NODE_TARGET_COL_WIDTH-1:0]);

                assign local_node_cfg_clr_pulse_match_w =
                    local_node_cfg_clr_pulse_i &&
                    (node_row_i == r[NODE_TARGET_ROW_WIDTH-1:0]) &&
                    (node_col_i == c[NODE_TARGET_COL_WIDTH-1:0]);

                assign p_up_thr_match_w = p_up_thr_w[r/2][c/2];
                assign lfsr_rnd_32_match_w = lfsr_rnd_32_w[r/2][c/2];
                pbit_node u_pbit_node (
                    .clk                        (clk),
                    .rst_n                      (rst_n),
                    .soft_rstn_i                (glb_soft_rstn_i),
       
                    .local_start_i              (local_start_w),
                    .num_majority_i             (num_majority_i),

                    .global_cfg_init_spin_i     (global_node_init_spin_w),
                    .global_cfg_clamp_en_i      (global_node_clamp_en_w),
                    .global_cfg_clamp_spin_i    (global_node_clamp_spin_w),
                    .global_cfg_bias_sign_i     (global_node_bias_sign_w),
                    .global_cfg_bias_prob_i     (global_node_bias_prob_w),
                    .global_cfg_vld_i           (global_node_cfg_vld_i),

                    .row_cfg_init_spin_i        (row_node_init_spin_w[r]),
                    .row_cfg_clamp_en_i         (row_node_clamp_en_w[r]),
                    .row_cfg_clamp_spin_i       (row_node_clamp_spin_w[r]),
                    .row_cfg_bias_sign_i        (row_node_bias_sign_w[r]),
                    .row_cfg_bias_prob_i        (row_node_bias_prob_w[r]),
                    .row_cfg_vld_i              (row_node_cfg_vld_i[r]),

                    .local_cfg_node_we_i        (local_node_cfg_we_match_w),
                    .local_cfg_clr_pulse_i      (local_node_cfg_clr_pulse_match_w),
                    .local_cfg_clr_all_pulse_i  (clr_local_all_pulse_i),
                    .local_node_cfg_i           (local_node_cfg_i),

                    .cfg_node_load_i            (node_load_pulse_i),
    
                    .rnd32_i                    (lfsr_rnd_32_match_w),

                    .neighbor_spin_n_i          (nbr_n[r][c]),
                    .neighbor_spin_ne_i         (nbr_ne[r][c]),
                    .neighbor_spin_e_i          (nbr_e[r][c]),
                    .neighbor_spin_se_i         (nbr_se[r][c]),
                    .neighbor_spin_s_i          (nbr_s[r][c]),
                    .neighbor_spin_sw_i         (nbr_sw[r][c]),
                    .neighbor_spin_w_i          (nbr_w[r][c]),
                    .neighbor_spin_nw_i         (nbr_nw[r][c]),
    
                    .edge_valid_n_i             (valid_n[r][c]),
                    .edge_valid_ne_i            (valid_ne[r][c]),
                    .edge_valid_e_i             (valid_e[r][c]),
                    .edge_valid_se_i            (valid_se[r][c]),
                    .edge_valid_s_i             (valid_s[r][c]),
                    .edge_valid_sw_i            (valid_sw[r][c]),
                    .edge_valid_w_i             (valid_w[r][c]),
                    .edge_valid_nw_i            (valid_nw[r][c]),
    
                    .edge_sign_n_i              (sign_n[r][c]),
                    .edge_sign_ne_i             (sign_ne[r][c]),
                    .edge_sign_e_i              (sign_e[r][c]),
                    .edge_sign_se_i             (sign_se[r][c]),
                    .edge_sign_s_i              (sign_s[r][c]),
                    .edge_sign_sw_i             (sign_sw[r][c]),
                    .edge_sign_w_i              (sign_w[r][c]),
                    .edge_sign_nw_i             (sign_nw[r][c]),
    
                    .edge_prob_n_i              (prob_n[r][c]),
                    .edge_prob_ne_i             (prob_ne[r][c]),
                    .edge_prob_e_i              (prob_e[r][c]),
                    .edge_prob_se_i             (prob_se[r][c]),
                    .edge_prob_s_i              (prob_s[r][c]),
                    .edge_prob_sw_i             (prob_sw[r][c]),
                    .edge_prob_w_i              (prob_w[r][c]),
                    .edge_prob_nw_i             (prob_nw[r][c]),

                    .macsum_o                   (macsum_w[r][c]),
                    .p_up_thr_i                 (p_up_thr_match_w),

                    .spin_o                     (spin[r][c])
                );
                assign spin_flat[r*COLS+c] = spin[r][c];//ROWS-COLS
            end
        end
    endgenerate

    //////////////////////////////////////////////////
    // shared tanh_lut_comb module for all p-bits
    //////////////////////////////////////////////////
    assign tanh_sel_w = {is_c3_q, is_c2_q, is_c1_q, is_c0_q};
    generate
        for(r = 0; r < TANH_ROWS; r = r + 1) begin : GEN_TANH_LUT_ROW
            for(c = 0; c < TANH_COLS; c = c + 1) begin : GEN_TANH_LUT_COL
                tanh_lut_comb u_tanh_lut_comb (
                    .i0_level_i (i0_level_i),
                    .h0_i (macsum_w[2*r][2*c]),
                    .h1_i (macsum_w[2*r][2*c+1]),
                    .h2_i (macsum_w[2*r+1][2*c]),
                    .h3_i (macsum_w[2*r+1][2*c+1]),
                    .tanh_sel_i (tanh_sel_w),
                    .p_up_thr_o (p_up_thr_w[r][c])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // shared lfsr32_rng32 module for all p-bits
    // ------------------------------------------------------------
    assign lfsr_en_w = is_c0_q | is_c1_q | is_c2_q | is_c3_q;
    generate
        for(r = 0; r < SEED_ROWS; r = r + 1) begin : GEN_LFSR32_R
            for(c = 0; c < SEED_COLS; c = c + 1) begin : GEN_LFSR32_C
                logic local_node_seed_we_match_w;
                logic local_node_seed_clr_pulse_match_w;

                assign local_node_seed_we_match_w =
                    local_node_seed_we_pulse_i &&
                    (node_row_i == r[NODE_TARGET_ROW_WIDTH-1:0]) &&
                    (node_col_i == c[NODE_TARGET_COL_WIDTH-1:0]);
                
                assign local_node_seed_clr_pulse_match_w =
                    local_node_seed_clr_pulse_i &&
                    (node_row_i == r[NODE_TARGET_ROW_WIDTH-1:0]) &&
                    (node_col_i == c[NODE_TARGET_COL_WIDTH-1:0]);

                lfsr32_rng32 u_lfsr32_rng32 (
                    .clk (clk),
                    .rst_n (rst_n),
                    .soft_rstn_i(glb_soft_rstn_i),
                    .local_seed_node_we_i(local_node_seed_we_match_w),
                    .local_seed_clr_pulse_i(local_node_seed_clr_pulse_match_w),
                    .local_seed_clr_all_pulse_i(clr_local_all_pulse_i),
                    .node_load_i(node_load_pulse_i),
                    .global_node_seed_i(global_node_seed_w),
                    .global_node_seed_vld_i(global_node_seed_vld_i),
                    .row_node_seed_i(row_node_seed_w[r]),
                    .row_node_seed_vld_i(row_node_seed_vld_i[r]),
                    .local_node_seed_i(local_node_seed_w),
                    .en_i (lfsr_en_w),
                    .rnd32_o (lfsr_rnd_32_w[r][c])
                );
            end
        end
    endgenerate
    // ------------------------------------------------------------
    // Horizontal edges:
    // A=(r,c), B=(r,c+1)
    // A sees B as E, B sees A as W
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_H_R
            for (c = 0; c < COLS-1; c = c + 1) begin : GEN_H_C

                logic cfg_we_h_w;
                logic cfg_clr_h_w;

                assign cfg_we_h_w =
                    cfg_edge_we_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_H) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                assign cfg_clr_h_w =
                    cfg_edge_clr_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_H) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                edge_reg_coupler u_edge_h (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .soft_rstn_i          (glb_soft_rstn_i),

                    .cfg_we_i             (cfg_we_h_w),
                    .cfg_clr_pulse_i      (cfg_clr_h_w),
                    .cfg_prob_i           (cfg_edge_prob_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r][c+1]),

                    .prob_to_a_o          (prob_e[r][c]),
                    .edge_sign_to_a_o     (sign_e[r][c]),
                    .valid_to_a_o         (valid_e[r][c]),
                    .neighbor_spin_to_a_o (nbr_e[r][c]),

                    .prob_to_b_o          (prob_w[r][c+1]),
                    .edge_sign_to_b_o     (sign_w[r][c+1]),
                    .valid_to_b_o         (valid_w[r][c+1]),
                    .neighbor_spin_to_b_o (nbr_w[r][c+1])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Vertical edges:
    // A=(r,c), B=(r+1,c)
    // A sees B as S, B sees A as N
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS-1; r = r + 1) begin : GEN_V_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_V_C

                logic cfg_we_v_w;
                logic cfg_clr_v_w;

                assign cfg_we_v_w =
                    cfg_edge_we_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_V) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                assign cfg_clr_v_w =
                    cfg_edge_clr_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_V) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                edge_reg_coupler u_edge_v (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .soft_rstn_i          (glb_soft_rstn_i),

                    .cfg_we_i             (cfg_we_v_w),
                    .cfg_clr_pulse_i      (cfg_clr_v_w),
                    .cfg_prob_i           (cfg_edge_prob_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r+1][c]),

                    .prob_to_a_o          (prob_s[r][c]),
                    .edge_sign_to_a_o     (sign_s[r][c]),
                    .valid_to_a_o         (valid_s[r][c]),
                    .neighbor_spin_to_a_o (nbr_s[r][c]),

                    .prob_to_b_o          (prob_n[r+1][c]),
                    .edge_sign_to_b_o     (sign_n[r+1][c]),
                    .valid_to_b_o         (valid_n[r+1][c]),
                    .neighbor_spin_to_b_o (nbr_n[r+1][c])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Diagonal SE edges:
    // A=(r,c), B=(r+1,c+1)
    // A sees B as SE, B sees A as NW
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS-1; r = r + 1) begin : GEN_DSE_R
            for (c = 0; c < COLS-1; c = c + 1) begin : GEN_DSE_C

                logic cfg_we_dse_w;
                logic cfg_clr_dse_w;

                assign cfg_we_dse_w =
                    cfg_edge_we_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_DSE) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                assign cfg_clr_dse_w =
                    cfg_edge_clr_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_DSE) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                edge_reg_coupler u_edge_dse (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .soft_rstn_i          (glb_soft_rstn_i),

                    .cfg_we_i             (cfg_we_dse_w),
                    .cfg_clr_pulse_i      (cfg_clr_dse_w),
                    .cfg_prob_i           (cfg_edge_prob_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r+1][c+1]),

                    .prob_to_a_o          (prob_se[r][c]),
                    .edge_sign_to_a_o     (sign_se[r][c]),
                    .valid_to_a_o         (valid_se[r][c]),
                    .neighbor_spin_to_a_o (nbr_se[r][c]),

                    .prob_to_b_o          (prob_nw[r+1][c+1]),
                    .edge_sign_to_b_o     (sign_nw[r+1][c+1]),
                    .valid_to_b_o         (valid_nw[r+1][c+1]),
                    .neighbor_spin_to_b_o (nbr_nw[r+1][c+1])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Diagonal SW edges:
    // A=(r,c), B=(r+1,c-1), c starts from 1
    // A sees B as SW, B sees A as NE
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS-1; r = r + 1) begin : GEN_DSW_R
            for (c = 1; c < COLS; c = c + 1) begin : GEN_DSW_C

                logic cfg_we_dsw_w;
                logic cfg_clr_dsw_w;

                assign cfg_we_dsw_w =
                    cfg_edge_we_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_DSW) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                assign cfg_clr_dsw_w =
                    cfg_edge_clr_pulse_i &&
                    (cfg_edge_type_i == EDGE_TYPE_EDGE_DSW) &&
                    (cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0]) &&
                    (cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0]);

                edge_reg_coupler u_edge_dsw (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .soft_rstn_i          (glb_soft_rstn_i),

                    .cfg_we_i             (cfg_we_dsw_w),
                    .cfg_clr_pulse_i      (cfg_clr_dsw_w),
                    .cfg_prob_i           (cfg_edge_prob_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r+1][c-1]),

                    .prob_to_a_o          (prob_sw[r][c]),
                    .edge_sign_to_a_o     (sign_sw[r][c]),
                    .valid_to_a_o         (valid_sw[r][c]),
                    .neighbor_spin_to_a_o (nbr_sw[r][c]),

                    .prob_to_b_o          (prob_ne[r+1][c-1]),
                    .edge_sign_to_b_o     (sign_ne[r+1][c-1]),
                    .valid_to_b_o         (valid_ne[r+1][c-1]),
                    .neighbor_spin_to_b_o (nbr_ne[r+1][c-1])
                );

            end
        end
    endgenerate

    // ------------------------------------------------------------
    // Snapshot Readback register's d port logic.
    // ------------------------------------------------------------
    generate
        for(r = 0; r < SPIN_ADDR_MAX; r++) begin : GEN_SPIN_FLAT_RESHAPE
            assign spin_flat_reshape[r] = spin_flat[r*SNAPSHOT_WIDTH+:SNAPSHOT_WIDTH];
        end
    endgenerate
    assign snapshot_flat_d = snapshot_addr_i < SPIN_ADDR_MAX? spin_flat_reshape[snapshot_addr_i] : {SNAPSHOT_WIDTH{1'b0}};
    assign snapshot_flat_en = snapshot_latch_pulse_i;
    assign snapshot_vld_d = snapshot_latch_pulse_i? 1'b1: snapshot_vld_q;

    dffe #(.WIDTH(SNAPSHOT_WIDTH)
    ) snapshot_flat_ff (
        .clk(clk),
        .en_i(snapshot_flat_en),
        .d_i(snapshot_flat_d),
        .q_o(snapshot_flat_q)
    );

    dffsr #(.WIDTH(1)
    ) snapshot_vld_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(snapshot_vld_d),
        .q_o(snapshot_vld_q)
    );

    // ------------------------------------------------------------
    // Done signal counter
    // 2*num_majority_act+2
    // ------------------------------------------------------------
    assign cnt_max        = {num_majority_i, 1'b0} + 2 + 1;

    assign is_c0_d        = phase_start_c0_i? 1'b1:
                            done_c0_d? 1'b0:
                            is_c0_q;

    assign is_c1_d        = phase_start_c1_i? 1'b1:
                            done_c1_d? 1'b0:
                            is_c1_q;

    assign is_c2_d        = phase_start_c2_i? 1'b1:
                            done_c2_d? 1'b0:
                            is_c2_q;

    assign is_c3_d        = phase_start_c3_i? 1'b1:
                            done_c3_d? 1'b0:
                            is_c3_q;

    assign done_c0_cnt_d  = (done_c0_cnt_q == cnt_max)? 0:
                            (phase_start_c0_i || |done_c0_cnt_q)? done_c0_cnt_q + 1:
                            done_c0_cnt_q;
    assign done_c0_cnt_en = (phase_start_c0_i || |done_c0_cnt_q);     
    assign done_c0_d      = done_c0_cnt_q == cnt_max; 

    assign done_c1_cnt_d  = (done_c1_cnt_q == cnt_max)? 0:
                            (phase_start_c1_i || |done_c1_cnt_q)? done_c1_cnt_q + 1:
                            done_c1_cnt_q;
    assign done_c1_cnt_en = (phase_start_c1_i || |done_c1_cnt_q);     
    assign done_c1_d      = done_c1_cnt_q == cnt_max;  

    assign done_c2_cnt_d  = (done_c2_cnt_q == cnt_max)? 0:
                            (phase_start_c2_i || |done_c2_cnt_q)? done_c2_cnt_q + 1:
                            done_c2_cnt_q;
    assign done_c2_cnt_en = (phase_start_c2_i || |done_c2_cnt_q);     
    assign done_c2_d      = done_c2_cnt_q == cnt_max;  

    assign done_c3_cnt_d  = (done_c3_cnt_q == cnt_max)? 0:
                            (phase_start_c3_i || |done_c3_cnt_q)? done_c3_cnt_q + 1:
                            done_c3_cnt_q;
    assign done_c3_cnt_en = (phase_start_c3_i || |done_c3_cnt_q);     
    assign done_c3_d      = done_c3_cnt_q == cnt_max;       

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH+2)
    ) done_c0_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .en_i(done_c0_cnt_en),
        .d_i(done_c0_cnt_d),
        .q_o(done_c0_cnt_q)
    );  

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH+2)
    ) done_c1_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .en_i(done_c1_cnt_en),
        .d_i(done_c1_cnt_d),
        .q_o(done_c1_cnt_q)
    );  

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH+2)
    ) done_c2_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .en_i(done_c2_cnt_en),
        .d_i(done_c2_cnt_d),
        .q_o(done_c2_cnt_q)
    );  

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH+2)
    ) done_c3_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .en_i(done_c3_cnt_en),
        .d_i(done_c3_cnt_d),
        .q_o(done_c3_cnt_q)
    );  

    dffsr #(.WIDTH(1)
    ) done_c0_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(done_c0_d),
        .q_o(done_c0_q)
    );

    dffsr #(.WIDTH(1)
    ) done_c1_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(done_c1_d),
        .q_o(done_c1_q)
    );

    dffsr #(.WIDTH(1)
    ) done_c2_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(done_c2_d),
        .q_o(done_c2_q)
    );

    dffsr #(.WIDTH(1)
    ) done_c3_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(done_c3_d),
        .q_o(done_c3_q)
    );

    dffsr #(.WIDTH(1)
    ) is_c0_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(is_c0_d),
        .q_o(is_c0_q)
    );

    dffsr #(.WIDTH(1)
    ) is_c1_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(is_c1_d),
        .q_o(is_c1_q)
    );

    dffsr #(.WIDTH(1)
    ) is_c2_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(is_c2_d),
        .q_o(is_c2_q)
    );

    dffsr #(.WIDTH(1)
    ) is_c3_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(is_c3_d),
        .q_o(is_c3_q)
    );
endmodule
`endif
