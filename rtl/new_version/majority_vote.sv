`ifndef MAJORITY_VOTE
`define MAJORITY_VOTE
import pbit_pkg::*;
module majority_vote (
    input  logic [NUM_MAJORITY_WIDTH:0]   spin_sum_i,
    input  logic                          majority_en_i,
    input  logic [NUM_MAJORITY_WIDTH-1:0] vote_threshold_i,
    output logic                          majority_o
);

    // BANK-generated minimum positive-vote count, range 1..17 for N=1..32.
    // The BANK accounts for the original tie rule when generating this threshold.
    // A set count MSB already exceeds every legal threshold.
    // Keep only a five-bit comparison on the remaining count bits.
    assign majority_o = majority_en_i &&
                        (spin_sum_i[NUM_MAJORITY_WIDTH] ||
                         (spin_sum_i[NUM_MAJORITY_WIDTH-1:0] >= vote_threshold_i));

endmodule
`endif
