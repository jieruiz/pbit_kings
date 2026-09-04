`ifndef COMPARATOR_VOTE
`define COMPARATOR_VOTE
import pbit_pkg::*;
module comparator_vote (
    input logic clk,
    input logic rst_n,
    input logic soft_rstn_i,

    // ------------------------------------------------------------
    // Shared 32_bit lfsr random int
    // ------------------------------------------------------------
    input logic [31:0] rnd32_i,

    // ------------------------------------------------------------
    // tah LUT port
    // ------------------------------------------------------------
    input logic [LUT_WIDTH-1:0] p_up_thr_i,

    // ------------------------------------------------------------
    // control
    // ------------------------------------------------------------
    input logic                          spin_sum_en_i,
    input logic                          majority_en_i,
    input logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,

    // ------------------------------------------------------------
    // output
    // ------------------------------------------------------------
    output logic majority_spin_o
);
    logic [31:0]          rnd32_w;
    logic [LUT_WIDTH-1:0] pbit_rand16_w;
    logic                 proposed_spin_w;

    logic [NUM_MAJORITY_WIDTH:0]    spin_sum_q, spin_sum_d;
    logic                           spin_sum_en;

    logic [NUM_MAJORITY_WIDTH:0] spin_sum_w;
    logic [NUM_MAJORITY_WIDTH:0] num_majority_act_w;
    logic                        majority_en;
    logic                        majority_spin_w;
    // ------------------------------------------------------------
    // p-bit proposal random
    // ------------------------------------------------------------
    assign rnd32_w = rnd32_i;
    
    pbit_rand16_extract u_pbit_rand16_extract (
        .rand32_i (rnd32_w),
        .rand16_o (pbit_rand16_w)
    );

    pbit_prob_compare16 u_pbit_prob_compare16 (
        .rand16_i (pbit_rand16_w),
        .prob16_i (p_up_thr_i),
        .accept_o (proposed_spin_w)
    );

    // ------------------------------------------------------------
    // spinsum
    // ------------------------------------------------------------
    assign spin_sum_d = majority_en? {(NUM_MAJORITY_WIDTH+1){1'b0}}: spin_sum_q + {{(NUM_MAJORITY_WIDTH){1'b0}}, proposed_spin_w};
    assign spin_sum_en = spin_sum_en_i;

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH+1)
    ) spin_sum_ff(
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .en_i(spin_sum_en),
        .d_i(spin_sum_d),
        .q_o(spin_sum_q)
    );

    // ------------------------------------------------------------
    // majority vote
    // ------------------------------------------------------------
    assign majority_en        = majority_en_i;
    assign spin_sum_w         = spin_sum_q;
    assign num_majority_act_w = num_majority_i + 1;
    assign majority_spin_o    = majority_spin_w;

    majority_vote u_majority_vote (
        .spin_sum_i         (spin_sum_w),
        .majority_en_i      (majority_en),
        .num_majority_act_i (num_majority_act_w),
        .majority_o         (majority_spin_w)
    );
endmodule
`endif