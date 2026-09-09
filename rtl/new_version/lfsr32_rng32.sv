`ifndef LFSR32_RNG32
`define LFSR32_RNG32
import pbit_pkg::*;
module lfsr32_rng32 (
    input  logic                             clk,
    input  logic                             rst_n,
    input  logic                             seed_we_i,
    input  logic [SEED_WIDTH-1:0]             seed_i,
    input  logic                             en_i,
    output logic [SEED_WIDTH-1:0]             rnd32_o
);

    logic [SEED_WIDTH-1:0] state_q, state_d;
    logic                  state_en;
    logic                  feedback;

    // One state is shared by node r/r+4. Advance on every enabled phase cycle.
    // Preserve the original 32-bit Fibonacci sequence and balance the XOR tree.
    assign feedback = (state_q[31] ^ state_q[21]) ^ (state_q[1] ^ state_q[0]);

    // pbit_reg converts zero seeds to one and suppresses seed writes throughout a run.
    // An accepted seed write has priority over advance; otherwise the FF enable holds state.
    assign state_d  = seed_we_i ? seed_i : {state_q[30:0], feedback};
    assign state_en = seed_we_i | en_i;
    // Seed readback observes this current state without a separate shadow register.
    assign rnd32_o = state_q;

    dffre #(.WIDTH(SEED_WIDTH),
           .RESET_VALUE({{(SEED_WIDTH-1){1'b0}}, 1'b1})
    ) state_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(state_en),
        .d_i(state_d),
        .q_o(state_q)
    );
endmodule
`endif
