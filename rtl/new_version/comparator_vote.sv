`ifndef COMPARATOR_VOTE
`define COMPARATOR_VOTE
import pbit_pkg::*;
module comparator_vote (
    input logic clk,
    input logic rst_n,

    // ------------------------------------------------------------
    // Shared 32-bit LFSR random input
    // ------------------------------------------------------------
    input logic [SEED_WIDTH-1:0] rnd32_i,

    // ------------------------------------------------------------
    // tanh LUT port
    // ------------------------------------------------------------
    input logic [LUT_WIDTH-1:0] p_up_thr_i,

    // ------------------------------------------------------------
    // control
    // ------------------------------------------------------------
    input logic                          spin_sum_en_i,
    input logic                          majority_en_i,
    input logic [NUM_MAJORITY_WIDTH-1:0] vote_threshold_i,

    // ------------------------------------------------------------
    // output
    // ------------------------------------------------------------
    output logic majority_spin_o
);
    logic [LUT_WIDTH-1:0] pbit_rand16_w;
    logic                 proposed_spin_w;

    // Six bits are required for 0..32 accepted proposals.
    logic [NUM_MAJORITY_WIDTH:0] spin_sum_q, spin_sum_d;
    logic                        spin_sum_en;

    // ------------------------------------------------------------
    // p-bit proposal random
    // ------------------------------------------------------------
    pbit_rand16_extract u_pbit_rand16_extract (
        .rand32_i (rnd32_i),
        .rand16_o (pbit_rand16_w)
    );

    pbit_prob_compare16 u_pbit_prob_compare16 (
        .rand16_i (pbit_rand16_w),
        .prob16_i (p_up_thr_i),
        .accept_o (proposed_spin_w)
    );

    // ------------------------------------------------------------
    // spin sum
    // ------------------------------------------------------------
    // Collect all samples before majority_en_i. At the commit edge the node
    // captures the vote from the old sum, while this shared accumulator clears.
    // Commit has priority over sampling and clears even when spin_sum_en_i=0.
    assign spin_sum_d = majority_en_i ? '0 :
                       spin_sum_q + {{NUM_MAJORITY_WIDTH{1'b0}}, proposed_spin_w};
    assign spin_sum_en = spin_sum_en_i | majority_en_i;

    // ------------------------------------------------------------
    // majority vote
    // ------------------------------------------------------------
    // The regional BANK supplies the minimum positive-vote count (1..17).
    // Keep this threshold stable throughout sampling and vote commit.
    majority_vote u_majority_vote (
        .spin_sum_i         (spin_sum_q),
        .majority_en_i      (majority_en_i),
        .vote_threshold_i   (vote_threshold_i),
        .majority_o         (majority_spin_o)
    );
    // ------------------------------------------------------------
    // Register instances
    // ------------------------------------------------------------
    dffre #(.WIDTH(NUM_MAJORITY_WIDTH+1)
    ) spin_sum_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(spin_sum_en),
        .d_i(spin_sum_d),
        .q_o(spin_sum_q)
    );
endmodule
`endif
