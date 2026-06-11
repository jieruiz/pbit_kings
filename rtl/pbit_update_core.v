`timescale 1ns / 1ps

module pbit_update_core_named #(
    parameter N_TRIAL = 5
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load_seed_i,
    input  wire [31:0] seed_i,

    input  wire        init_spin_we_i,
    input  wire        init_spin_i,

    // clamp control
    input  wire        clamp_en_i,
    input  wire        clamp_spin_i,
    input  wire        bias_sign_i,
    input  wire [3:0]  bias_prob4_i,

    input  wire        start_i,
    input  wire [3:0]  i0_level_i,

    // neighbor spins
    input wire neighbor_spin_n_i,
    input wire neighbor_spin_ne_i,
    input wire neighbor_spin_e_i,
    input wire neighbor_spin_se_i,
    input wire neighbor_spin_s_i,
    input wire neighbor_spin_sw_i,
    input wire neighbor_spin_w_i,
    input wire neighbor_spin_nw_i,

    // edge valid
    input wire edge_valid_n_i,
    input wire edge_valid_ne_i,
    input wire edge_valid_e_i,
    input wire edge_valid_se_i,
    input wire edge_valid_s_i,
    input wire edge_valid_sw_i,
    input wire edge_valid_w_i,
    input wire edge_valid_nw_i,

    // edge signs: 1 means J=+1, 0 means J=-1
    input wire edge_sign_n_i,
    input wire edge_sign_ne_i,
    input wire edge_sign_e_i,
    input wire edge_sign_se_i,
    input wire edge_sign_s_i,
    input wire edge_sign_sw_i,
    input wire edge_sign_w_i,
    input wire edge_sign_nw_i,

    // 4-bit edge probability thresholds
    input wire [3:0] edge_prob_n_i,
    input wire [3:0] edge_prob_ne_i,
    input wire [3:0] edge_prob_e_i,
    input wire [3:0] edge_prob_se_i,
    input wire [3:0] edge_prob_s_i,
    input wire [3:0] edge_prob_sw_i,
    input wire [3:0] edge_prob_w_i,
    input wire [3:0] edge_prob_nw_i,

    output wire       spin_o,
    output reg        busy_o,
    output reg        done_o,
    output reg        flip_o,

    // debug
    output reg signed [4:0] dbg_h_i_o,
    output reg [3:0]        dbg_plus_count_o,
    output reg [31:0]       dbg_edge_rand32_o,
    output reg [15:0]       dbg_pbit_rand16_o,
    output wire [7:0]       dbg_edge_accept_o
);

    localparam S_IDLE       = 3'd0;
    localparam S_EDGE_RAND  = 3'd1;
    localparam S_EDGE_USE   = 3'd2;
    localparam S_PBIT_RAND  = 3'd3;
    localparam S_PBIT_USE   = 3'd4;
    localparam S_MAJORITY   = 3'd5;

    reg [2:0] state_q;

    reg       spin_q;
    reg [2:0] trial_idx_q;

    reg signed [4:0] h_i_q;

    reg [N_TRIAL-1:0] votes_q;
    reg               last_vote_q;

    wire [31:0] rnd32_w;
    wire        rnd_valid_w;

    wire lfsr_en_w;

    // Clamp mode disables random generation.
    assign lfsr_en_w =
        (!clamp_en_i) &&
        (
            (state_q == S_EDGE_RAND) ||
            (state_q == S_PBIT_RAND)
        );

    lfsr32_rng32 u_lfsr32_rng32 (
        .clk         (clk),
        .rst_n       (rst_n),
        .load_seed_i (load_seed_i),
        .seed_i      (seed_i),
        .en_i        (lfsr_en_w),
        .rnd32_o     (rnd32_w),
        .rnd_valid_o (rnd_valid_w)
    );

    // ------------------------------------------------------------
    // 8 edge probability compares
    // ------------------------------------------------------------

    wire accept_n_w;
    wire accept_ne_w;
    wire accept_e_w;
    wire accept_se_w;
    wire accept_s_w;
    wire accept_sw_w;
    wire accept_w_w;
    wire accept_nw_w;
    wire accept_bias_w;

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

    assign dbg_edge_accept_o = {
        accept_nw_w,
        accept_w_w,
        accept_sw_w,
        accept_s_w,
        accept_se_w,
        accept_e_w,
        accept_ne_w,
        accept_n_w
    };

    // Bias uses the local p-bit LFSR bits 8, 6, 4, and 2 as one 4-bit draw.
    wire [3:0] bias_rand4_w;
    assign bias_rand4_w = {
        rnd32_w[8],
        rnd32_w[6],
        rnd32_w[4],
        rnd32_w[2]
    };

    edge_prob_compare4 u_bias_prob_compare4 (
        .rand4_i  (bias_rand4_w),
        .prob4_i  (bias_prob4_i),
        .valid_i  (1'b1),
        .accept_o (accept_bias_w)
    );

    // ------------------------------------------------------------
    // 8 edge contribution compute
    // ------------------------------------------------------------

    wire signed [4:0] h_sum_w;
    wire signed [1:0] bias_contrib_w;
    wire signed [4:0] bias_contrib_ext_w;
    wire signed [4:0] h_sum_with_bias_w;

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
        .edge_sign_i     (bias_sign_i),
        .neighbor_spin_i (1'b1),
        .contrib_o       (bias_contrib_w)
    );

    assign bias_contrib_ext_w = {{3{bias_contrib_w[1]}}, bias_contrib_w};
    assign h_sum_with_bias_w  = h_sum_w + bias_contrib_ext_w;

    // ------------------------------------------------------------
    // tanh LUT
    // ------------------------------------------------------------

    wire [15:0] p_up_thr_w;

    tanh_lut_comb u_tanh_lut_comb (
        .i0_level_i (i0_level_i),
        .h_i        (h_i_q),
        .p_up_thr_o (p_up_thr_w)
    );

    // ------------------------------------------------------------
    // p-bit proposal random
    // ------------------------------------------------------------

    wire [15:0] pbit_rand16_w;
    wire        proposed_spin_w;

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

    wire       majority_spin_w;
    wire [3:0] plus_count_w;

    majority_vote #(
        .N_TRIAL(N_TRIAL)
    ) u_majority_vote (
        .votes_i      (votes_q),
        .last_vote_i  (last_vote_q),
        .majority_o   (majority_spin_w),
        .plus_count_o (plus_count_w)
    );

    assign spin_o = spin_q;

    // ------------------------------------------------------------
    // FSM with clamp
    // ------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= S_IDLE;

            spin_q             <= 1'b0;
            trial_idx_q        <= 3'd0;

            h_i_q              <= 5'sd0;
            votes_q            <= {N_TRIAL{1'b0}};
            last_vote_q        <= 1'b0;

            busy_o             <= 1'b0;
            done_o             <= 1'b0;
            flip_o             <= 1'b0;

            dbg_h_i_o          <= 5'sd0;
            dbg_plus_count_o   <= 4'd0;
            dbg_edge_rand32_o  <= 32'd0;
            dbg_pbit_rand16_o  <= 16'd0;
        end else begin
            done_o <= 1'b0;
            flip_o <= 1'b0;

            // ----------------------------------------------------
            // Highest-priority clamp path.
            // If clamp is active, this p-bit is forced to clamp_spin_i.
            // No LFSR, no tanh, no edge sampling.
            // ----------------------------------------------------
            if (clamp_en_i) begin
                if (busy_o || start_i) begin
                    done_o <= 1'b1;
                    flip_o <= spin_q ^ clamp_spin_i;
                end

                spin_q      <= clamp_spin_i;
                state_q     <= S_IDLE;
                busy_o      <= 1'b0;
                trial_idx_q <= 3'd0;

                votes_q     <= {N_TRIAL{1'b0}};
                last_vote_q <= clamp_spin_i;

                dbg_h_i_o        <= 5'sd0;
                dbg_plus_count_o <= 4'd0;
            end else begin
                // Initial spin write is only allowed in IDLE/config phase.
                if ((state_q == S_IDLE) && init_spin_we_i) begin
                    spin_q <= init_spin_i;
                end

                case (state_q)

                    S_IDLE: begin
                        busy_o <= 1'b0;

                        if (start_i && !load_seed_i) begin
                            busy_o      <= 1'b1;
                            trial_idx_q <= 3'd0;
                            votes_q     <= {N_TRIAL{1'b0}};
                            last_vote_q <= 1'b0;
                            state_q     <= S_EDGE_RAND;
                        end
                    end

                    S_EDGE_RAND: begin
                        state_q <= S_EDGE_USE;
                    end

                    S_EDGE_USE: begin
                        // Python sampled_local_field returns -h.
                        h_i_q             <= -h_sum_with_bias_w;
                        dbg_h_i_o         <= -h_sum_with_bias_w;
                        dbg_edge_rand32_o <= rnd32_w;

                        state_q           <= S_PBIT_RAND;
                    end

                    S_PBIT_RAND: begin
                        state_q <= S_PBIT_USE;
                    end

                    S_PBIT_USE: begin
                        votes_q[trial_idx_q] <= proposed_spin_w;
                        last_vote_q          <= proposed_spin_w;
                        dbg_pbit_rand16_o    <= pbit_rand16_w;

                        if (trial_idx_q == (N_TRIAL - 1)) begin
                            state_q <= S_MAJORITY;
                        end else begin
                            trial_idx_q <= trial_idx_q + 3'd1;
                            state_q     <= S_EDGE_RAND;
                        end
                    end

                    S_MAJORITY: begin
                        spin_q           <= majority_spin_w;
                        flip_o           <= spin_q ^ majority_spin_w;
                        dbg_plus_count_o <= plus_count_w;

                        busy_o           <= 1'b0;
                        done_o           <= 1'b1;

                        state_q          <= S_IDLE;
                    end

                    default: begin
                        state_q <= S_IDLE;
                    end

                endcase
            end
        end
    end

endmodule
