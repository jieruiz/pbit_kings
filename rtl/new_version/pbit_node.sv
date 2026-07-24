`ifndef PBIT_NODE
`define PBIT_NODE
import pbit_pkg::*;
module pbit_node (
    input  logic clk,
    input  logic rst_n,
    input  logic soft_rstn_i,
    // ------------------------------------------------------------
    // Local phase start.
    // This is already color-decoded by array-level wiring.
    // ------------------------------------------------------------
    input  logic                          local_start_i,
    input  logic                          run_done_clr_pulse_i,
    input  logic [I0_LEVEL_WIDTH-1:0]     i0_level_i,
    input  logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,
    // ------------------------------------------------------------
    // Node configuration interface.
    // Used during CONFIG phase.
    // ------------------------------------------------------------
    input  logic [NODE_SEED_WIDTH-1:0]           global_cfg_seed_i,      
    input  logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  global_cfg_init_spin_i, 
    input  logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   global_cfg_clamp_en_i,  
    input  logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] global_cfg_clamp_spin_i,
    input  logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  global_cfg_bias_sign_i, 
    input  logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  global_cfg_bias_prob_i,
    input  logic                                 global_cfg_vld_i,
 
    input  logic [NODE_SEED_WIDTH-1:0]           row_cfg_seed_i,      
    input  logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  row_cfg_init_spin_i, 
    input  logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   row_cfg_clamp_en_i,  
    input  logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] row_cfg_clamp_spin_i,
    input  logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  row_cfg_bias_sign_i, 
    input  logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  row_cfg_bias_prob_i,
    input  logic                                 row_cfg_vld_i,
                                 
    input  logic                                 local_cfg_node_we_i       ,
    input  logic                                 local_cfg_node_seed_we_i  ,
    input  logic                                 local_cfg_clr_pulse_i     ,
    input  logic                                 local_cfg_clr_all_pulse_i ,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]     local_node_cfg_i          ,
    input  logic [NODE_SEED_WIDTH-1:0]           local_cfg_seed_i          ,


    output logic [NODE_CFG_W-1:0]               local_node_rcfg_o,
    output logic [NODE_SEED_WIDTH-1:0]          local_node_rseed_o,

    input logic                                 cfg_node_load_i,

    // ------------------------------------------------------------
    // Neighbor spins
    // ------------------------------------------------------------
    input logic neighbor_spin_n_i,
    input logic neighbor_spin_ne_i,
    input logic neighbor_spin_e_i,
    input logic neighbor_spin_se_i,
    input logic neighbor_spin_s_i,
    input logic neighbor_spin_sw_i,
    input logic neighbor_spin_w_i,
    input logic neighbor_spin_nw_i,

    // ------------------------------------------------------------
    // Edge valid
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_n_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_ne_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_e_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_se_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_s_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_sw_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_w_i,
    input logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] edge_valid_nw_i,

    // ------------------------------------------------------------
    // Edge sign: 1 means J=+1, 0 means J=-1
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_n_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_ne_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_e_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_se_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_s_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_sw_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_w_i,
    input logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0] edge_sign_nw_i,

    // ------------------------------------------------------------
    // Edge probability, 4-bit
    // ------------------------------------------------------------
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_n_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_ne_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_e_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_se_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_s_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_sw_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w_i,
    input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_nw_i,

    // ------------------------------------------------------------
    // Runtime outputs
    // ------------------------------------------------------------
    output logic       spin_o,
    output logic       busy_o,
    output logic       done_hold_o
);
    typedef enum logic [1:0] {
        S_IDLE,
        S_EDGE,
        S_PBIT,
        S_MAJORITY
    } state_e;
    // ------------------------------------------------------------
    // Clamp and bias registers.
    // ------------------------------------------------------------
    logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  local_cfg_init_spin_w ; 
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   local_cfg_clamp_en_w  ; 
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] local_cfg_clamp_spin_w; 
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  local_cfg_bias_sign_w ; 
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  local_cfg_bias_prob_w;     
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   clamp_en_q, clamp_en_d;
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] clamp_spin_q, clamp_spin_d;
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_q, bias_sign_d;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_q, bias_prob_d;
    logic bias_prob_en;
    logic local_cfg_vld_q, local_cfg_vld_d;

    // ------------------------------------------------------------
    // 32-bit lfsr
    // ------------------------------------------------------------
    logic  [31:0] rnd32_w;
    logic         lfsr_en_w;

    // ------------------------------------------------------------
    // 8 edge probability compares
    // ------------------------------------------------------------
    logic accept_n_w;
    logic accept_ne_w;
    logic accept_e_w;
    logic accept_se_w;
    logic accept_s_w;
    logic accept_sw_w;
    logic accept_w_w;
    logic accept_nw_w;

    // ------------------------------------------------------------
    // bias probability compares
    // ------------------------------------------------------------
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_rand_w;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_w;
    logic accept_bias_w;

    // ------------------------------------------------------------
    // 8 edge contribution compute
    // ------------------------------------------------------------
    logic signed [MACSUM_WIDTH-1:0] h_sum_w;
    logic signed [1:0] bias_contrib_w;
    logic signed [MACSUM_WIDTH-1:0] bias_contrib_ext_w;
    logic signed [MACSUM_WIDTH-1:0] h_sum_with_bias_w;

    // ------------------------------------------------------------
    // tanh LUT
    // ------------------------------------------------------------
    logic [LUT_WIDTH-1:0] p_up_thr_w;

    // ------------------------------------------------------------
    // p-bit proposal random
    // ------------------------------------------------------------
    logic [LUT_WIDTH-1:0] pbit_rand16_w;
    logic                 proposed_spin_w;

    // ------------------------------------------------------------
    // majority vote
    // ------------------------------------------------------------
    logic [NUM_MAJORITY_MAX-1:0] votes_w;
    logic                        majority_en_w;
    logic                        majority_spin_w;

    // ------------------------------------------------------------
    // FSM+output
    // ------------------------------------------------------------
    state_e                         state_q, state_d;    
    logic                           spin_q, spin_d;         
    logic [NUM_MAJORITY_WIDTH-1:0]  trial_idx_q, trial_idx_d;
    logic                           trial_idx_en;
    logic [MACSUM_WIDTH-1:0]        macsum_q_raw;
    logic signed [MACSUM_WIDTH-1:0] macsum_q, macsum_d;
    logic                           macsum_en;
    logic [NUM_MAJORITY_MAX-1:0]    votes_q, votes_d;
    logic                           votes_en;
    logic                           done_hold_q, done_hold_d;
    // ------------------------------------------------------------
    // Clamp and bias registers.
    // ------------------------------------------------------------
    assign local_cfg_init_spin_w  = local_node_cfg_i[NODE_CFG_INIT_SPIN_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB];
    assign local_cfg_clamp_en_w   = local_node_cfg_i[NODE_CFG_CLAMP_EN_PACKED_MSB:NODE_CFG_CLAMP_EN_PACKED_LSB];
    assign local_cfg_clamp_spin_w = local_node_cfg_i[NODE_CFG_CLAMP_SPIN_PACKED_MSB:NODE_CFG_CLAMP_SPIN_PACKED_LSB];
    assign local_cfg_bias_sign_w  = local_node_cfg_i[NODE_CFG_BIAS_SIGN_PACKED_MSB:NODE_CFG_BIAS_SIGN_PACKED_LSB];
    assign local_cfg_bias_prob_w  = local_node_cfg_i[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_BIAS_PROB_PACKED_LSB];
    assign clamp_en_d = local_cfg_node_we_i? local_node_cfg_i[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? local_cfg_clamp_en_w: clamp_en_q: 
                        cfg_node_load_i? local_cfg_vld_q? clamp_en_q:
                                         row_cfg_vld_i? row_cfg_clamp_en_i:
                                         global_cfg_vld_i? global_cfg_clamp_en_i: 
                                         clamp_en_q:
                        clamp_en_q;
    assign clamp_spin_d = local_cfg_node_we_i? local_node_cfg_i[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? local_cfg_clamp_spin_w: clamp_spin_q:
                          cfg_node_load_i? local_cfg_vld_q? clamp_spin_q:
                                           row_cfg_vld_i? row_cfg_clamp_spin_i:
                                           global_cfg_vld_i? global_cfg_clamp_spin_i: 
                                           clamp_spin_q:
                          clamp_spin_q;
    assign bias_sign_d = local_cfg_node_we_i? local_node_cfg_i[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? local_cfg_bias_sign_w: bias_sign_q: 
                         cfg_node_load_i? local_cfg_vld_q? bias_sign_q:
                                          row_cfg_vld_i? row_cfg_bias_sign_i:
                                          global_cfg_vld_i? global_cfg_bias_sign_i: 
                                          bias_sign_q:
                         bias_sign_q;
    assign bias_prob_d = local_cfg_node_we_i? local_node_cfg_i[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? local_cfg_bias_prob_w: bias_prob_q: 
                          cfg_node_load_i? local_cfg_vld_q? bias_prob_q:
                                           row_cfg_vld_i? row_cfg_bias_prob_i:
                                           global_cfg_vld_i? global_cfg_bias_prob_i: 
                                           bias_prob_q:
                          bias_prob_q;
    assign bias_prob_en = local_cfg_node_we_i | cfg_node_load_i;
    assign local_cfg_vld_d = local_cfg_node_we_i & !local_cfg_clr_pulse_i & !local_cfg_clr_all_pulse_i;
    assign local_node_rcfg_o = {bias_prob_q, bias_sign_q, clamp_spin_q, clamp_en_q, spin_q};

    dffsr #(.WIDTH(NODE_CFG_CLAMP_EN_WIDTH)
    ) clamp_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .d_i(clamp_en_d),
        .q_o(clamp_en_q)
    );

    dff #(.WIDTH(NODE_CFG_CLAMP_SPIN_WIDTH)
    ) clamp_spin_ff (
        .clk(clk),
        .d_i(clamp_spin_d),
        .q_o(clamp_spin_q)
    );

    dff #(.WIDTH(NODE_CFG_BIAS_SIGN_WIDTH)
    ) bias_sign_ff (
        .clk(clk),
        .d_i(bias_sign_d),
        .q_o(bias_sign_q)
    );

    dffe #(.WIDTH(NODE_CFG_BIAS_PROB_WIDTH)
    ) bias_prob_ff (
        .clk(clk),
        .en_i(bias_prob_en),
        .d_i(bias_prob_d),
        .q_o(bias_prob_q)
    );

    dff #(.WIDTH(1)
    ) local_cfg_vld_ff (
        .clk(clk),
        .d_i(local_cfg_vld_d),
        .q_o(local_cfg_vld_q)
    );

    // ------------------------------------------------------------
    // 32-bit lfsr
    // ------------------------------------------------------------
    assign local_node_rseed_o = rnd32_w;
    assign lfsr_en_w =
        (!clamp_en_q) &&
        (
            (state_d == S_EDGE) ||
            (state_d == S_PBIT)
        );

    lfsr32_rng32 u_lfsr32_rng32 (
        .clk         (clk),
        .rst_n       (rst_n),
        .soft_rstn_i (soft_rstn_i),

        .local_seed_we_i (local_cfg_node_seed_we_i),
        .cfg_node_load_i (cfg_node_load_i),
        .global_cfg_seed_i (global_cfg_seed_i),
        .global_cfg_vld_i (global_cfg_vld_i),
        .row_cfg_seed_i (row_cfg_seed_i),
        .row_cfg_vld_i (row_cfg_vld_i),
        .local_node_cfg_i (local_node_cfg_i),
        .local_cfg_seed_i (local_cfg_seed_i),
        .local_cfg_vld_i (local_cfg_vld_q),
        .en_i        (lfsr_en_w),
        .rnd32_o     (rnd32_w),
        .rnd_valid_o ()
    );

    // ------------------------------------------------------------
    // 8 edge probability compares
    // ------------------------------------------------------------
    edge_compare8_named u_edge_compare8_named (
        .edge_rand32_i  (rnd32_w),

        .edge_prob_n_i  (edge_prob_n_i),
        .edge_prob_ne_i (edge_prob_ne_i),
        .edge_prob_e_i  (edge_prob_e_i),
        .edge_prob_se_i (edge_prob_se_i),
        .edge_prob_s_i  (edge_prob_s_i),
        .edge_prob_sw_i (edge_prob_sw_i),
        .edge_prob_w_i  (edge_prob_w_i),
        .edge_prob_nw_i (edge_prob_nw_i),

        .edge_valid_n_i  (edge_valid_n_i),
        .edge_valid_ne_i (edge_valid_ne_i),
        .edge_valid_e_i  (edge_valid_e_i),
        .edge_valid_se_i (edge_valid_se_i),
        .edge_valid_s_i  (edge_valid_s_i),
        .edge_valid_sw_i (edge_valid_sw_i),
        .edge_valid_w_i  (edge_valid_w_i),
        .edge_valid_nw_i (edge_valid_nw_i),

        .accept_n_o  (accept_n_w),
        .accept_ne_o (accept_ne_w),
        .accept_e_o  (accept_e_w),
        .accept_se_o (accept_se_w),
        .accept_s_o  (accept_s_w),
        .accept_sw_o (accept_sw_w),
        .accept_w_o  (accept_w_w),
        .accept_nw_o (accept_nw_w)
    );

    // ------------------------------------------------------------
    // bias probability compares
    // ------------------------------------------------------------
    assign bias_rand_w = {
        rnd32_w[12],
        rnd32_w[10],        
        rnd32_w[8],
        rnd32_w[6],
        rnd32_w[4],
        rnd32_w[2],
        rnd32_w[0]
    };
    assign bias_prob_w = bias_prob_q;
    edge_prob_compare #(
        .WIDTH(NODE_CFG_BIAS_PROB_WIDTH)    
    ) u_bias_prob_compare (
        .rand_i   (bias_rand_w),
        .prob_i   (bias_prob_w),
        .valid_i  (1'b1),
        .accept_o (accept_bias_w)
    );

    // ------------------------------------------------------------
    // 8 edge contribution compute
    // ------------------------------------------------------------
    pbit_8edge_compute u_pbit_8edge_compute (
        .accept_n_i  (accept_n_w),
        .accept_ne_i (accept_ne_w),
        .accept_e_i  (accept_e_w),
        .accept_se_i (accept_se_w),
        .accept_s_i  (accept_s_w),
        .accept_sw_i (accept_sw_w),
        .accept_w_i  (accept_w_w),
        .accept_nw_i (accept_nw_w),

        .edge_sign_n_i  (edge_sign_n_i),
        .edge_sign_ne_i (edge_sign_ne_i),
        .edge_sign_e_i  (edge_sign_e_i),
        .edge_sign_se_i (edge_sign_se_i),
        .edge_sign_s_i  (edge_sign_s_i),
        .edge_sign_sw_i (edge_sign_sw_i),
        .edge_sign_w_i  (edge_sign_w_i),
        .edge_sign_nw_i (edge_sign_nw_i),

        .neighbor_spin_n_i  (neighbor_spin_n_i),
        .neighbor_spin_ne_i (neighbor_spin_ne_i),
        .neighbor_spin_e_i  (neighbor_spin_e_i),
        .neighbor_spin_se_i (neighbor_spin_se_i),
        .neighbor_spin_s_i  (neighbor_spin_s_i),
        .neighbor_spin_sw_i (neighbor_spin_sw_i),
        .neighbor_spin_w_i  (neighbor_spin_w_i),
        .neighbor_spin_nw_i (neighbor_spin_nw_i),

        .h_sum_o (h_sum_w)
    );

    pbit_edge_contrib2 u_bias_contrib (
        .accept_i        (accept_bias_w),
        .edge_sign_i     (bias_sign_q),
        .neighbor_spin_i (1'b1),
        .contrib_o       (bias_contrib_w)
    );

    assign bias_contrib_ext_w = $signed({{3{bias_contrib_w[1]}}, bias_contrib_w});
    assign h_sum_with_bias_w  = h_sum_w + bias_contrib_ext_w;

    // ------------------------------------------------------------
    // tanh LUT
    // ------------------------------------------------------------
    tanh_lut_comb u_tanh_lut_comb (
        .i0_level_i (i0_level_i),
        .h_i        (macsum_q),
        .p_up_thr_o (p_up_thr_w)
    );

    // ------------------------------------------------------------
    // p-bit proposal random
    // ------------------------------------------------------------
    pbit_rand16_extract u_pbit_rand16_extract (
        .rand32_i (rnd32_w),
        .rand16_o (pbit_rand16_w)
    );

    pbit_prob_compare16 u_pbit_prob_compare16 (
        .rand16_i (pbit_rand16_w),
        .prob16_i (p_up_thr_w),
        .accept_o (proposed_spin_w)
    );

    // ------------------------------------------------------------
    // majority vote
    // ------------------------------------------------------------
    assign majority_en_w = state_q == S_MAJORITY;
    assign votes_w = votes_q;
    majority_vote u_majority_vote (
        .votes_i       (votes_w),
        .majority_en_i (majority_en_w),
        .num_majority_i(num_majority_i),
        .majority_o    (majority_spin_w)
    );

    // ------------------------------------------------------------
    // FSM+output
    // ------------------------------------------------------------
    always @(*) begin
        case(state_q)
            S_IDLE: begin
                if(!clamp_en_q && local_start_i) state_d = S_EDGE;
                else state_d = S_IDLE;
            end
            S_EDGE: begin
                state_d = S_PBIT;
            end
            S_PBIT: begin
                if(trial_idx_q == num_majority_i-1) state_d = S_MAJORITY;
                else state_d = S_EDGE;
            end
            S_MAJORITY: begin
                state_d = S_IDLE;
            end
            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    assign spin_d = clamp_en_q? clamp_spin_q:
                    (state_q == S_IDLE)? local_cfg_node_we_i? local_node_cfg_i[INIT_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB]? local_cfg_init_spin_w: spin_q:
                                         cfg_node_load_i? local_cfg_vld_q? spin_q:
                                                          row_cfg_vld_i? row_cfg_init_spin_i:
                                                          global_cfg_vld_i? global_cfg_init_spin_i:
                                                          spin_q:
                                         spin_q:
                    (state_q == S_MAJORITY)? majority_spin_w:
                    spin_q;
    assign spin_o = spin_q;
    assign trial_idx_d = (clamp_en_q || (state_q == S_IDLE))? {NUM_MAJORITY_WIDTH{1'b0}}:
                         ((state_q == S_PBIT) && (state_d == S_EDGE))? trial_idx_q + {{(NUM_MAJORITY_WIDTH-1){1'b0}}, 1'b1}:
                         trial_idx_q;
    assign trial_idx_en = clamp_en_q || (state_q == S_IDLE) || (state_q == S_PBIT);
    assign macsum_d = h_sum_with_bias_w;
    assign macsum_en = (state_q == S_EDGE) || (state_d == S_PBIT);
    assign macsum_q = $signed(macsum_q_raw);
    assign votes_d = (state_q == S_PBIT)? {votes_d[NUM_MAJORITY_MAX-2:0], proposed_spin_w}: {NUM_MAJORITY_MAX{1'b0}};
    assign votes_en = (state_q == S_PBIT) || (state_q == S_IDLE);
    assign busy_o = !clamp_en_q && (state_q != S_IDLE);
    assign done_hold_o = done_hold_q;
    assign done_hold_d = (~local_start_i & ~run_done_clr_pulse_i)? 1'b0:
                         (state_q == S_MAJORITY)? 1'b1:
                         done_hold_q;

    always_ff @(posedge clk or negedge rst_n) begin : state_ff
        if(~rst_n) begin
            state_q <= S_IDLE;
        end else if(~soft_rstn_i) begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    dff #(.WIDTH(1)
    ) spin_ff (
        .clk(clk),
        .d_i(spin_d),
        .q_o(spin_q)
    );

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH)
    ) trial_idx_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .en_i(trial_idx_en),
        .d_i(trial_idx_d),
        .q_o(trial_idx_q)
    );

    dffe #(.WIDTH(5)
    ) macsum_ff (
        .clk(clk),
        .en_i(macsum_en),
        .d_i($unsigned(macsum_d)),
        .q_o(macsum_q_raw)
    );

    dffe #(.WIDTH(NUM_MAJORITY_MAX)
    ) votes_ff(
        .clk(clk),
        .en_i(votes_en),
        .d_i(votes_d),
        .q_o(votes_q)
    );

    dffsr #(.WIDTH(1)
    ) done_hold_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .d_i(done_hold_d),
        .q_o(done_hold_q)
    );
endmodule
`endif