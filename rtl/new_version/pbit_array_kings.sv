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
    input  logic                                 phase_start_i,

    input  logic [3:0]                           current_phase_i,

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
    input  wire  [NODE_SEED_WIDTH-1:0]           row_node_seed_i[0:SHARED_ROWS-1],
    input  logic [ROWS-1:0]                      row_node_cfg_vld_i,
    input  logic [SHARED_ROWS-1:0]                 row_node_seed_vld_i,

    input  logic                                 local_node_cfg_we_pulse_i,
    input  logic                                 local_node_cfg_clr_pulse_i,
    input  logic                                 local_node_seed_we_pulse_i,
    input  logic                                 local_node_seed_clr_pulse_i,
    input  logic [TARGET_MODE_WIDTH-1:0]         node_target_mode_i,
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

    //Node readback IO 
    input  logic                                 node_rdata_cfg_pulse_i,
    input  logic                                 node_rdata_seed_pulse_i,
    output logic [NODE_CFG_W-1:0]                node_rdata_cfg_o,
    output logic [NODE_SEED_WIDTH-1:0]           node_rdata_seed_o,
 
    //Edge readback IO 
    input  logic                                 edge_rdata_pulse_i,
    output logic [EDGE_RDATA_PACKED_WIDTH-1:0]   edge_rdata_cfg_o,
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
    // SCALED_STRUCT_SYNC: Use generate indices for the parameterized regional bank topology.
    genvar tanh_bank_r;
    genvar tanh_bank_c;
    genvar tanh_h;

    // ------------------------------------------------------------
    // Snapshot Readback.
    // ------------------------------------------------------------
    logic [SNAPSHOT_WIDTH-1:0] snapshot_flat_q, snapshot_flat_d;
    logic snapshot_flat_en;
    logic snapshot_vld_q, snapshot_vld_d;

    assign snapshot_flat_o = snapshot_flat_q;
    assign snapshot_vld_o  = snapshot_vld_q;

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
    logic [NODE_SEED_WIDTH-1:0]           row_node_seed_w[SHARED_ROWS];

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
        
        for(r = 0; r < SHARED_ROWS; r++) begin: ROW_NODE_SEED_DECODE
            assign row_node_seed_w[r]       = row_node_seed_i[r];
        end
    endgenerate

    assign local_node_seed_w       = local_node_seed_i;

    // ------------------------------------------------------------
    // Node spin
    // ------------------------------------------------------------
    logic [ROWS-1:0]                     node_row_hit;
    logic [COLS-1:0]                     node_col_hit;

    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign_w[ROWS][COLS];
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_w[ROWS][COLS];
    logic                                spin [ROWS][COLS];
    // SCALED_STRUCT_SYNC: Reserve complete snapshot pages; padding is zero for the current 40x40 array.
    localparam int SNAPSHOT_STORAGE_WIDTH = SPIN_ADDR_MAX * SNAPSHOT_WIDTH;
    localparam int SNAPSHOT_PAD_WIDTH = SNAPSHOT_STORAGE_WIDTH - N_SPIN;
    logic [N_SPIN-1:0]                   spin_flat;
    logic [SNAPSHOT_STORAGE_WIDTH-1:0]   spin_flat_padded;
    logic [SNAPSHOT_WIDTH-1:0]           spin_flat_reshape[SPIN_ADDR_MAX];

    // ------------------------------------------------------------
    // Node readback
    // ------------------------------------------------------------
    logic [NODE_CFG_W-1:0] local_node_rcfg_w[ROWS][COLS];
    logic [NODE_SEED_WIDTH-1:0] local_node_rseed_w[SHARED_ROWS][SHARED_COLS];
    logic [NODE_CFG_W-1:0] node_rdata_cfg_q, node_rdata_cfg_d;
    logic node_rdata_cfg_en;
    logic [NODE_SEED_WIDTH-1:0] node_rdata_seed_q, node_rdata_seed_d;
    logic node_rdata_seed_en;

    assign node_rdata_cfg_o = node_rdata_cfg_q;
    assign node_rdata_seed_o = node_rdata_seed_q;
    // ------------------------------------------------------------
    // Edge readback
    // ------------------------------------------------------------
    logic [EDGE_RDATA_PACKED_WIDTH-1:0] edge_rdata_cfg_q, edge_rdata_cfg_d;
    logic edge_rdata_cfg_en;

    assign edge_rdata_cfg_o = edge_rdata_cfg_q;

    // ------------------------------------------------------------
    // Directional wires into each p-bit
    // ------------------------------------------------------------
    logic type_hit_h, type_hit_v, type_hit_dse, type_hit_dsw;
    logic [ROWS-1:0] edge_row_hit;
    logic [COLS-1:0] edge_col_hit;

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
    logic                       lfsr_en_w;
    logic [NODE_SEED_WIDTH-1:0] lfsr_rnd_32_w[0:SHARED_ROWS-1][0:SHARED_COLS-1];

    // ------------------------------------------------------------
    // mac
    // ------------------------------------------------------------
    logic [3:0]                     mac_sel_w;
    logic                           mac_en_w;
    logic signed [MACSUM_WIDTH-1:0] macsum_w[0:SHARED_ROWS-1][0:SHARED_COLS-1];

    // ------------------------------------------------------------
    // tanh LUT wires
    // ------------------------------------------------------------
    // SCALED_STRUCT_SYNC: Parameterize bank dimensions; each bank serves at most 10x10 shared tiles.
    logic [LUT_WIDTH-1:0]           tanh_pos_thr_by_abs_d [0:TANH_BANK_ROWS-1][0:TANH_BANK_COLS-1][0:9];
    logic [LUT_WIDTH-1:0]           tanh_pos_thr_by_abs_q [0:TANH_BANK_ROWS-1][0:TANH_BANK_COLS-1][0:9];
    logic [LUT_WIDTH-1:0]           p_up_thr_w[0:SHARED_ROWS-1][0:SHARED_COLS-1];

    // ------------------------------------------------------------
    // comparator_vote
    // ------------------------------------------------------------
    logic spin_sum_en_w;
    logic majority_en_w;
    logic majority_spin_w[0:SHARED_ROWS-1][0:SHARED_COLS-1];

    // ------------------------------------------------------------
    // Done signal counter
    // num_majority_act+1+2
    // ------------------------------------------------------------
    logic done_q, done_d;

    logic [NUM_MAJORITY_WIDTH+1:0] done_cnt_q, done_cnt_d;
    logic done_cnt_en;

    logic [NUM_MAJORITY_WIDTH+1:0] cnt_max;

    //assign all_done_c0_o = done_c0_q;
    //assign all_done_c1_o = done_c1_q;
    //assign all_done_c2_o = done_c2_q;
    //assign all_done_c3_o = done_c3_q;

    assign all_done_c0_o = done_q & current_phase_i[0];
    assign all_done_c1_o = done_q & current_phase_i[1];
    assign all_done_c2_o = done_q & current_phase_i[2];
    assign all_done_c3_o = done_q & current_phase_i[3];

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
    // p-bit node controller
    // ------------------------------------------------------------
    pbit_control u_pbit_control (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .soft_rstn_i            (glb_soft_rstn_i),

        .phase_start_i          (phase_start_i),

        .num_majority_i         (num_majority_i),

        .mac_en_o               (mac_en_w),
        .spin_sum_en_o          (spin_sum_en_w),
        .majority_en_o          (majority_en_w)
    );

    // ------------------------------------------------------------
    // Instantiate all p-bit nodes.
    // Compile-time color:
    // color = 2*(row%2) + (col%2)
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_NODE_HIT_R
            assign node_row_hit[r] = node_row_i == r[NODE_TARGET_ROW_WIDTH-1:0];
        end

        for (c = 0; c < COLS; c = c + 1) begin : GEN_NODE_HIT_C
            assign node_col_hit[c] = node_col_i == c[NODE_TARGET_COL_WIDTH-1:0];
        end
    endgenerate

    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_NODE_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_NODE_C

                localparam integer CELL_COLOR = (r % 2) * 2 + (c % 2);

                logic majority_en_match_w;
                logic majority_spin_match_w;
                logic local_node_cfg_we_match_w;
                logic local_node_cfg_clr_pulse_match_w;

                assign majority_en_match_w   = majority_en_w && current_phase_i[CELL_COLOR];
                assign majority_spin_match_w = majority_spin_w[r/2][c/2];

                assign local_node_cfg_we_match_w        = local_node_cfg_we_pulse_i && node_row_hit[r] && node_col_hit[c];

                assign local_node_cfg_clr_pulse_match_w = local_node_cfg_clr_pulse_i && node_row_hit[r] && node_col_hit[c];

                pbit_node u_pbit_node (
                    .clk                        (clk),
                    .rst_n                      (rst_n),
       
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

                    .local_node_rcfg_o          (local_node_rcfg_w[r][c]),

                    .cfg_node_load_i            (node_load_pulse_i),

                    .bias_sign_o                (bias_sign_w[r][c]),
                    .bias_prob_o                (bias_prob_w[r][c]),

                    .majority_en_i              (majority_en_match_w),
                    .majority_spin_i            (majority_spin_match_w),

                    .spin_o                     (spin[r][c])
                );
                assign spin_flat[r*COLS+c] = spin[r][c];//ROWS-COLS
            end
        end
    endgenerate

    //////////////////////////////////////////////////
    // shared mac module for all p-bits
    //////////////////////////////////////////////////
    assign mac_sel_w = current_phase_i;
    generate
        for(r = 0; r < SHARED_ROWS; r = r + 1) begin : GEN_MAC_ROW
            for(c = 0; c < SHARED_COLS; c = c + 1) begin : GEN_MAC_COL
                mac u_mac (
                    .clk        (clk),

                    .mac_sel_i  (mac_sel_w),

                    .rnd32_i    (lfsr_rnd_32_w[r][c]),
                    
                    .bias_sign_0_i(bias_sign_w[r*2][c*2]),
                    .bias_prob_0_i(bias_prob_w[r*2][c*2]),

                    .neighbor_spin_n_0_i  (nbr_n[r*2][c*2]),
                    .neighbor_spin_ne_0_i (nbr_ne[r*2][c*2]),
                    .neighbor_spin_e_0_i  (nbr_e[r*2][c*2]),
                    .neighbor_spin_se_0_i (nbr_se[r*2][c*2]),
                    .neighbor_spin_s_0_i  (nbr_s[r*2][c*2]),
                    .neighbor_spin_sw_0_i (nbr_sw[r*2][c*2]),
                    .neighbor_spin_w_0_i  (nbr_w[r*2][c*2]),
                    .neighbor_spin_nw_0_i (nbr_nw[r*2][c*2]),

                    .edge_valid_n_0_i     (valid_n[r*2][c*2]),
                    .edge_valid_ne_0_i    (valid_ne[r*2][c*2]),
                    .edge_valid_e_0_i     (valid_e[r*2][c*2]),
                    .edge_valid_se_0_i    (valid_se[r*2][c*2]),
                    .edge_valid_s_0_i     (valid_s[r*2][c*2]),
                    .edge_valid_sw_0_i    (valid_sw[r*2][c*2]),
                    .edge_valid_w_0_i     (valid_w[r*2][c*2]),
                    .edge_valid_nw_0_i    (valid_nw[r*2][c*2]),

                    .edge_sign_n_0_i      (sign_n[r*2][c*2]),
                    .edge_sign_ne_0_i     (sign_ne[r*2][c*2]),
                    .edge_sign_e_0_i      (sign_e[r*2][c*2]),
                    .edge_sign_se_0_i     (sign_se[r*2][c*2]),
                    .edge_sign_s_0_i      (sign_s[r*2][c*2]),
                    .edge_sign_sw_0_i     (sign_sw[r*2][c*2]),
                    .edge_sign_w_0_i      (sign_w[r*2][c*2]),
                    .edge_sign_nw_0_i     (sign_nw[r*2][c*2]),  

                    .edge_prob_n_0_i      (prob_n[r*2][c*2]),
                    .edge_prob_ne_0_i     (prob_ne[r*2][c*2]),
                    .edge_prob_e_0_i      (prob_e[r*2][c*2]),
                    .edge_prob_se_0_i     (prob_se[r*2][c*2]),
                    .edge_prob_s_0_i      (prob_s[r*2][c*2]),
                    .edge_prob_sw_0_i     (prob_sw[r*2][c*2]),
                    .edge_prob_w_0_i      (prob_w[r*2][c*2]),
                    .edge_prob_nw_0_i     (prob_nw[r*2][c*2]),

                    .bias_sign_1_i(bias_sign_w[r*2][c*2+1]),
                    .bias_prob_1_i(bias_prob_w[r*2][c*2+1]),

                    .neighbor_spin_n_1_i  (nbr_n[r*2][c*2+1]),
                    .neighbor_spin_ne_1_i (nbr_ne[r*2][c*2+1]),
                    .neighbor_spin_e_1_i  (nbr_e[r*2][c*2+1]),
                    .neighbor_spin_se_1_i (nbr_se[r*2][c*2+1]),
                    .neighbor_spin_s_1_i  (nbr_s[r*2][c*2+1]),
                    .neighbor_spin_sw_1_i (nbr_sw[r*2][c*2+1]),
                    .neighbor_spin_w_1_i  (nbr_w[r*2][c*2+1]),
                    .neighbor_spin_nw_1_i (nbr_nw[r*2][c*2+1]),

                    .edge_valid_n_1_i     (valid_n[r*2][c*2+1]),
                    .edge_valid_ne_1_i    (valid_ne[r*2][c*2+1]),
                    .edge_valid_e_1_i     (valid_e[r*2][c*2+1]),
                    .edge_valid_se_1_i    (valid_se[r*2][c*2+1]),
                    .edge_valid_s_1_i     (valid_s[r*2][c*2+1]),
                    .edge_valid_sw_1_i    (valid_sw[r*2][c*2+1]),
                    .edge_valid_w_1_i     (valid_w[r*2][c*2+1]),
                    .edge_valid_nw_1_i    (valid_nw[r*2][c*2+1]),

                    .edge_sign_n_1_i      (sign_n[r*2][c*2+1]),
                    .edge_sign_ne_1_i     (sign_ne[r*2][c*2+1]),
                    .edge_sign_e_1_i      (sign_e[r*2][c*2+1]),
                    .edge_sign_se_1_i     (sign_se[r*2][c*2+1]),
                    .edge_sign_s_1_i      (sign_s[r*2][c*2+1]),
                    .edge_sign_sw_1_i     (sign_sw[r*2][c*2+1]),
                    .edge_sign_w_1_i      (sign_w[r*2][c*2+1]),
                    .edge_sign_nw_1_i     (sign_nw[r*2][c*2+1]),  

                    .edge_prob_n_1_i      (prob_n[r*2][c*2+1]),
                    .edge_prob_ne_1_i     (prob_ne[r*2][c*2+1]),
                    .edge_prob_e_1_i      (prob_e[r*2][c*2+1]),
                    .edge_prob_se_1_i     (prob_se[r*2][c*2+1]),
                    .edge_prob_s_1_i      (prob_s[r*2][c*2+1]),
                    .edge_prob_sw_1_i     (prob_sw[r*2][c*2+1]),
                    .edge_prob_w_1_i      (prob_w[r*2][c*2+1]),
                    .edge_prob_nw_1_i     (prob_nw[r*2][c*2+1]),       

                    .bias_sign_2_i(bias_sign_w[r*2+1][c*2]),
                    .bias_prob_2_i(bias_prob_w[r*2+1][c*2]),

                    .neighbor_spin_n_2_i  (nbr_n[r*2+1][c*2]),
                    .neighbor_spin_ne_2_i (nbr_ne[r*2+1][c*2]),
                    .neighbor_spin_e_2_i  (nbr_e[r*2+1][c*2]),
                    .neighbor_spin_se_2_i (nbr_se[r*2+1][c*2]),
                    .neighbor_spin_s_2_i  (nbr_s[r*2+1][c*2]),
                    .neighbor_spin_sw_2_i (nbr_sw[r*2+1][c*2]),
                    .neighbor_spin_w_2_i  (nbr_w[r*2+1][c*2]),
                    .neighbor_spin_nw_2_i (nbr_nw[r*2+1][c*2]),

                    .edge_valid_n_2_i     (valid_n[r*2+1][c*2]),
                    .edge_valid_ne_2_i    (valid_ne[r*2+1][c*2]),
                    .edge_valid_e_2_i     (valid_e[r*2+1][c*2]),
                    .edge_valid_se_2_i    (valid_se[r*2+1][c*2]),
                    .edge_valid_s_2_i     (valid_s[r*2+1][c*2]),
                    .edge_valid_sw_2_i    (valid_sw[r*2+1][c*2]),
                    .edge_valid_w_2_i     (valid_w[r*2+1][c*2]),
                    .edge_valid_nw_2_i    (valid_nw[r*2+1][c*2]),

                    .edge_sign_n_2_i      (sign_n[r*2+1][c*2]),
                    .edge_sign_ne_2_i     (sign_ne[r*2+1][c*2]),
                    .edge_sign_e_2_i      (sign_e[r*2+1][c*2]),
                    .edge_sign_se_2_i     (sign_se[r*2+1][c*2]),
                    .edge_sign_s_2_i      (sign_s[r*2+1][c*2]),
                    .edge_sign_sw_2_i     (sign_sw[r*2+1][c*2]),
                    .edge_sign_w_2_i      (sign_w[r*2+1][c*2]),
                    .edge_sign_nw_2_i     (sign_nw[r*2+1][c*2]),  

                    .edge_prob_n_2_i      (prob_n[r*2+1][c*2]),
                    .edge_prob_ne_2_i     (prob_ne[r*2+1][c*2]),
                    .edge_prob_e_2_i      (prob_e[r*2+1][c*2]),
                    .edge_prob_se_2_i     (prob_se[r*2+1][c*2]),
                    .edge_prob_s_2_i      (prob_s[r*2+1][c*2]),
                    .edge_prob_sw_2_i     (prob_sw[r*2+1][c*2]),
                    .edge_prob_w_2_i      (prob_w[r*2+1][c*2]),
                    .edge_prob_nw_2_i     (prob_nw[r*2+1][c*2]),         

                    .bias_sign_3_i(bias_sign_w[r*2+1][c*2+1]),
                    .bias_prob_3_i(bias_prob_w[r*2+1][c*2+1]),

                    .neighbor_spin_n_3_i  (nbr_n[r*2+1][c*2+1]),
                    .neighbor_spin_ne_3_i (nbr_ne[r*2+1][c*2+1]),
                    .neighbor_spin_e_3_i  (nbr_e[r*2+1][c*2+1]),
                    .neighbor_spin_se_3_i (nbr_se[r*2+1][c*2+1]),
                    .neighbor_spin_s_3_i  (nbr_s[r*2+1][c*2+1]),
                    .neighbor_spin_sw_3_i (nbr_sw[r*2+1][c*2+1]),
                    .neighbor_spin_w_3_i  (nbr_w[r*2+1][c*2+1]),
                    .neighbor_spin_nw_3_i (nbr_nw[r*2+1][c*2+1]),

                    .edge_valid_n_3_i     (valid_n[r*2+1][c*2+1]),
                    .edge_valid_ne_3_i    (valid_ne[r*2+1][c*2+1]),
                    .edge_valid_e_3_i     (valid_e[r*2+1][c*2+1]),
                    .edge_valid_se_3_i    (valid_se[r*2+1][c*2+1]),
                    .edge_valid_s_3_i     (valid_s[r*2+1][c*2+1]),
                    .edge_valid_sw_3_i    (valid_sw[r*2+1][c*2+1]),
                    .edge_valid_w_3_i     (valid_w[r*2+1][c*2+1]),
                    .edge_valid_nw_3_i    (valid_nw[r*2+1][c*2+1]),

                    .edge_sign_n_3_i      (sign_n[r*2+1][c*2+1]),
                    .edge_sign_ne_3_i     (sign_ne[r*2+1][c*2+1]),
                    .edge_sign_e_3_i      (sign_e[r*2+1][c*2+1]),
                    .edge_sign_se_3_i     (sign_se[r*2+1][c*2+1]),
                    .edge_sign_s_3_i      (sign_s[r*2+1][c*2+1]),
                    .edge_sign_sw_3_i     (sign_sw[r*2+1][c*2+1]),
                    .edge_sign_w_3_i      (sign_w[r*2+1][c*2+1]),
                    .edge_sign_nw_3_i     (sign_nw[r*2+1][c*2+1]),  

                    .edge_prob_n_3_i      (prob_n[r*2+1][c*2+1]),
                    .edge_prob_ne_3_i     (prob_ne[r*2+1][c*2+1]),
                    .edge_prob_e_3_i      (prob_e[r*2+1][c*2+1]),
                    .edge_prob_se_3_i     (prob_se[r*2+1][c*2+1]),
                    .edge_prob_s_3_i      (prob_s[r*2+1][c*2+1]),
                    .edge_prob_sw_3_i     (prob_sw[r*2+1][c*2+1]),
                    .edge_prob_w_3_i      (prob_w[r*2+1][c*2+1]),
                    .edge_prob_nw_3_i     (prob_nw[r*2+1][c*2+1]),

                    .macsum_en_i          (mac_en_w),
                    .macsum_o             (macsum_w[r][c])           
                );
            end
        end
    endgenerate

    // SCALED_STRUCT_SYNC: Generate the regional bank grid from package parameters (still 2x2 at 40x40).
    generate
        for (tanh_bank_r = 0; tanh_bank_r < TANH_BANK_ROWS; tanh_bank_r = tanh_bank_r + 1) begin : GEN_TANH_BANK_R
            for (tanh_bank_c = 0; tanh_bank_c < TANH_BANK_COLS; tanh_bank_c = tanh_bank_c + 1) begin : GEN_TANH_BANK_C
                tanh_threshold_bank u_tanh_threshold_bank (
                    .i0_level_i       (i0_level_i),
                    .pos_thr_by_abs_o (tanh_pos_thr_by_abs_d[tanh_bank_r][tanh_bank_c])
                );

                // TIMING_OPT_TANH_BANK_REG: Break the round-to-vote path after each regional LUT bank.
                // The threshold table is registered continuously because i0 changes only at round boundaries.
                for (tanh_h = 0; tanh_h < 10; tanh_h = tanh_h + 1) begin : GEN_TANH_BANK_THR_FF
                    dff #(
                        .WIDTH(LUT_WIDTH)
                    ) u_tanh_threshold_ff (
                        .clk (clk),
                        // SCALED_STRUCT_SYNC: Preserve the threshold pipeline registers with the new bank indices.
                        .d_i (tanh_pos_thr_by_abs_d[tanh_bank_r][tanh_bank_c][tanh_h]),
                        .q_o (tanh_pos_thr_by_abs_q[tanh_bank_r][tanh_bank_c][tanh_h])
                    );
                end
            end
        end
    endgenerate

    // SCALED_STRUCT_SYNC: Select each tile's bank using the configured region size at elaboration time.
    generate
        for(r = 0; r < SHARED_ROWS; r = r + 1) begin : GEN_TANH_LUT_ROW
            for(c = 0; c < SHARED_COLS; c = c + 1) begin : GEN_TANH_LUT_COL
                tanh_threshold_select u_tanh_threshold_select (
                    .h_i              (macsum_w[r][c]),
                    .pos_thr_by_abs_i (tanh_pos_thr_by_abs_q[r / TANH_BANK_TILE_ROWS]
                                                                 [c / TANH_BANK_TILE_COLS]),
                    .p_up_thr_o       (p_up_thr_w[r][c])
                );
            end
        end
    endgenerate

    //////////////////////////////////////////////////
    // shared comparator_vote for all p-bits
    //////////////////////////////////////////////////
    generate
        for(r = 0; r < SHARED_ROWS; r = r + 1) begin : GEN_COMPARATOR_VOTE_ROW
            for(c = 0; c < SHARED_COLS; c = c + 1) begin : GEN_COMPARATOR_VOTE_COL
                comparator_vote u_comparator_vote (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .soft_rstn_i(glb_soft_rstn_i),

                    .rnd32_i    (lfsr_rnd_32_w[r][c]),

                    .p_up_thr_i (p_up_thr_w[r][c]),

                    .spin_sum_en_i  (spin_sum_en_w),
                    .majority_en_i  (majority_en_w),
                    .num_majority_i (num_majority_i),

                    .majority_spin_o (majority_spin_w[r][c])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // shared lfsr32_rng32 module for all p-bits
    // ------------------------------------------------------------
    assign lfsr_en_w = |current_phase_i;
    generate
        for(r = 0; r < SHARED_ROWS; r = r + 1) begin : GEN_LFSR32_R
            for(c = 0; c < SHARED_COLS; c = c + 1) begin : GEN_LFSR32_C
                logic local_node_seed_we_match_w;
                logic local_node_seed_clr_pulse_match_w;

                assign local_node_seed_we_match_w = local_node_seed_we_pulse_i && node_row_hit[r] && node_col_hit[c];
                assign local_node_seed_clr_pulse_match_w = local_node_seed_clr_pulse_i  && node_row_hit[r] && node_col_hit[c];

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
    assign type_hit_h   = cfg_edge_type_i == EDGE_TYPE_EDGE_H;
    assign type_hit_v   = cfg_edge_type_i == EDGE_TYPE_EDGE_V;
    assign type_hit_dse = cfg_edge_type_i == EDGE_TYPE_EDGE_DSE;
    assign type_hit_dsw = cfg_edge_type_i == EDGE_TYPE_EDGE_DSW;

    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_EDGE_HIT_R
            assign edge_row_hit[r] = cfg_edge_row_i == r[EDGE_TARGET_ROW_WIDTH-1:0];
        end

        for (c = 0; c < COLS; c = c + 1) begin : GEN_EDGE_HIT_C
            assign edge_col_hit[c] = cfg_edge_col_i == c[EDGE_TARGET_COL_WIDTH-1:0];
        end
    endgenerate

    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_H_R
            for (c = 0; c < COLS-1; c = c + 1) begin : GEN_H_C

                logic cfg_we_h_w;
                logic cfg_clr_h_w;

                assign cfg_we_h_w  = cfg_edge_we_pulse_i && type_hit_h && edge_row_hit[r] && edge_col_hit[c];
                assign cfg_clr_h_w = cfg_edge_clr_pulse_i && type_hit_h && edge_row_hit[r] && edge_col_hit[c];

                edge_reg_coupler u_edge_h (
                    .clk                  (clk),
                    .rst_n                (rst_n),

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

                assign cfg_we_v_w  = cfg_edge_we_pulse_i && type_hit_v && edge_row_hit[r] && edge_col_hit[c];
                assign cfg_clr_v_w = cfg_edge_clr_pulse_i && type_hit_v && edge_row_hit[r] && edge_col_hit[c];

                edge_reg_coupler u_edge_v (
                    .clk                  (clk),
                    .rst_n                (rst_n),
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

                assign cfg_we_dse_w  = cfg_edge_we_pulse_i && type_hit_dse && edge_row_hit[r] && edge_col_hit[c];
                assign cfg_clr_dse_w = cfg_edge_clr_pulse_i && type_hit_dse && edge_row_hit[r] && edge_col_hit[c];

                edge_reg_coupler u_edge_dse (
                    .clk                  (clk),
                    .rst_n                (rst_n),

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

                assign cfg_we_dsw_w  = cfg_edge_we_pulse_i && type_hit_dsw && edge_row_hit[r] && edge_col_hit[c];
                assign cfg_clr_dsw_w = cfg_edge_clr_pulse_i && type_hit_dsw && edge_row_hit[r] && edge_col_hit[c];

                edge_reg_coupler u_edge_dsw (
                    .clk                  (clk),
                    .rst_n                (rst_n),

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
        // SCALED_STRUCT_SYNC: Zero-pad only an incomplete last page; current 40x40 data passes through unchanged.
        if (SNAPSHOT_PAD_WIDTH == 0) begin : GEN_SNAPSHOT_NO_PAD
            assign spin_flat_padded = spin_flat;
        end else begin : GEN_SNAPSHOT_PAD
            assign spin_flat_padded = {{SNAPSHOT_PAD_WIDTH{1'b0}}, spin_flat};
        end
    endgenerate
    generate
        // SCALED_STRUCT_SYNC: Slice full pages from the padded vector without changing spin bit ordering.
        for(r = 0; r < SPIN_ADDR_MAX; r++) begin : GEN_SPIN_FLAT_RESHAPE
            assign spin_flat_reshape[r] = spin_flat_padded[r*SNAPSHOT_WIDTH+:SNAPSHOT_WIDTH];
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
    // Node readback
    // ------------------------------------------------------------
    generate
        for(r = 0; r < SHARED_ROWS; r++) begin : GEN_NODE_SEED_RDATA_ROW
            for(c = 0; c < SHARED_COLS; c++) begin : GEN_NODE_SEED_RDATA_COL
                assign local_node_rseed_w[r][c] = lfsr_rnd_32_w[r][c];
            end
        end
    endgenerate

    always @(*) begin
        case(node_target_mode_i)
            TARGET_MODE_GLOBAL: begin
                node_rdata_cfg_d  = global_node_cfg_i;
                node_rdata_seed_d = global_node_seed_i;
            end
            TARGET_MODE_ROW: begin
                if(node_row_i < ROWS)
                    node_rdata_cfg_d  = row_node_cfg_i[node_row_i];
                else node_rdata_cfg_d = {NODE_CFG_W{1'b0}};
                if(node_row_i < SHARED_ROWS)
                    node_rdata_seed_d = row_node_seed_i[node_row_i];
                else node_rdata_seed_d = {NODE_SEED_WIDTH{1'b0}};
            end
            TARGET_MODE_LOCAL: begin
                if(node_row_i < ROWS && node_col_i < COLS)
                    node_rdata_cfg_d  = local_node_rcfg_w[node_row_i][node_col_i];
                else node_rdata_cfg_d = {NODE_CFG_W{1'b0}};
                if(node_row_i < SHARED_ROWS && node_col_i < SHARED_COLS)
                    node_rdata_seed_d = local_node_rseed_w[node_row_i][node_col_i];
                else node_rdata_seed_d = {NODE_SEED_WIDTH{1'b0}};
            end
            default: begin
                node_rdata_cfg_d  = {NODE_CFG_W{1'b0}};
                node_rdata_seed_d = {NODE_SEED_WIDTH{1'b0}};
            end
        endcase
    end

    assign node_rdata_cfg_en  = node_rdata_cfg_pulse_i;
    assign node_rdata_seed_en = node_rdata_seed_pulse_i;

    dffe #(.WIDTH(NODE_CFG_W)
    ) node_rdata_cfg_ff (
        .clk(clk),
        .en_i(node_rdata_cfg_en),
        .d_i(node_rdata_cfg_d),
        .q_o(node_rdata_cfg_q)
    );

    dffe #(.WIDTH(NODE_SEED_WIDTH)
    ) node_rdata_seed_ff (
        .clk(clk),
        .en_i(node_rdata_seed_en),
        .d_i(node_rdata_seed_d),
        .q_o(node_rdata_seed_q)
    );

    // ------------------------------------------------------------
    // Edge readback
    // ------------------------------------------------------------
    always @(*) begin
        if(cfg_edge_row_i < ROWS && cfg_edge_col_i < COLS)
            case(cfg_edge_type_i)
                EDGE_TYPE_EDGE_H: begin
                    edge_rdata_cfg_d = {prob_e[cfg_edge_row_i][cfg_edge_col_i], sign_e[cfg_edge_row_i][cfg_edge_col_i], valid_e[cfg_edge_row_i][cfg_edge_col_i]};
                end
                EDGE_TYPE_EDGE_V: begin
                    edge_rdata_cfg_d = {prob_s[cfg_edge_row_i][cfg_edge_col_i], sign_s[cfg_edge_row_i][cfg_edge_col_i], valid_s[cfg_edge_row_i][cfg_edge_col_i]};
                end
                EDGE_TYPE_EDGE_DSE: begin
                    edge_rdata_cfg_d = {prob_se[cfg_edge_row_i][cfg_edge_col_i], sign_se[cfg_edge_row_i][cfg_edge_col_i], valid_se[cfg_edge_row_i][cfg_edge_col_i]};
                end
                EDGE_TYPE_EDGE_DSW: begin
                    edge_rdata_cfg_d = {prob_sw[cfg_edge_row_i][cfg_edge_col_i], sign_sw[cfg_edge_row_i][cfg_edge_col_i], valid_sw[cfg_edge_row_i][cfg_edge_col_i]};
                end
                default: begin
                    edge_rdata_cfg_d = {EDGE_RDATA_PACKED_WIDTH{1'b0}};
                end
            endcase
        else edge_rdata_cfg_d = {EDGE_RDATA_PACKED_WIDTH{1'b0}};
    end
    assign edge_rdata_cfg_en = edge_rdata_pulse_i;

    dffe #(.WIDTH(EDGE_RDATA_PACKED_WIDTH)
    ) edge_rdata_cfg_ff (
        .clk(clk),
        .en_i(edge_rdata_cfg_en),
        .d_i(edge_rdata_cfg_d),
        .q_o(edge_rdata_cfg_q)
    );
    // ------------------------------------------------------------
    // Done signal counter
    // num_majority_act+1+2
    // ------------------------------------------------------------
    assign cnt_max        = (num_majority_i + 1) + 1 + 2 - 1;

    assign done_cnt_d  = (done_cnt_q == cnt_max)? 0:
                         (phase_start_i || |done_cnt_q)? done_cnt_q + 1:
                         done_cnt_q;
    assign done_cnt_en = (phase_start_i || |done_cnt_q);     
    assign done_d      = done_cnt_q == cnt_max; 

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH+2)
    ) done_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .en_i(done_cnt_en),
        .d_i(done_cnt_d),
        .q_o(done_cnt_q)
    );  

    dffsr #(.WIDTH(1)
    ) done_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i(done_d),
        .q_o(done_q)
    );
endmodule
`endif
