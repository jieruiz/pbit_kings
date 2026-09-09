`ifndef PHASE_CONTROL
`define PHASE_CONTROL
import pbit_pkg::*;
module phase_control (
    input  logic clk,
    input  logic rst_n,
    input  logic cfg_done_i,
    input  logic run_start_pulse_i,
    input  logic run_done_clr_pulse_i,
    // Preserve the original count encoding: actual sweeps = configured value + 1.
    input  logic [NUM_SWEEP_WIDTH-1:0] num_sweeps_i,
    input  wire [I0_LEVEL_WIDTH-1:0] i0_level_i [SWEEP_ROUND_NUM],
    // Each stage lasts configured interval + 1 complete two-phase sweeps.
    input  wire [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_i [SWEEP_ROUND_NUM],
    input  logic all_phase_done_i,
    output logic phase_start_o,
    output logic phase_o,
    output logic [I0_LEVEL_WIDTH-1:0] i0_level_o,
    output logic run_busy_o,
    output logic run_done_o
);
    typedef enum logic [1:0] {S_IDLE, S_WAIT_C0, S_WAIT_C1} state_e;
    state_e state_q, state_d;
    logic run_accept_w, phase0_done_w, sweep_done_w, next_sweep_w, run_finish_w;
    logic interval_done_w, round_last_w, counters_en_w;
    logic phase_start_d, run_done_d;
    logic [NUM_SWEEP_WIDTH-1:0] sweep_cnt_q, sweep_cnt_d;
    logic [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_cnt_q, sweep_interval_cnt_d;
    logic [SWEEP_ROUND_WIDTH-1:0] sweep_round_cnt_q, sweep_round_cnt_d;

    assign run_accept_w = (state_q == S_IDLE) && cfg_done_i && run_start_pulse_i;
    assign phase0_done_w = (state_q == S_WAIT_C0) && all_phase_done_i;
    assign sweep_done_w = (state_q == S_WAIT_C1) && all_phase_done_i;
    assign run_finish_w = sweep_done_w && (sweep_cnt_q == num_sweeps_i);
    assign next_sweep_w = sweep_done_w && !run_finish_w;
    assign interval_done_w = (sweep_interval_cnt_q == sweep_interval_i[sweep_round_cnt_q]);
    assign round_last_w = (sweep_round_cnt_q == SWEEP_ROUND_WIDTH'(SWEEP_ROUND_NUM-1));

    always @(*) begin
        state_d = state_q;
        case (state_q)
            S_IDLE: if (run_accept_w) state_d = S_WAIT_C0;
            S_WAIT_C0: if (phase0_done_w) state_d = S_WAIT_C1;
            S_WAIT_C1: if (sweep_done_w) state_d = run_finish_w ? S_IDLE : S_WAIT_C0;
            default: state_d = S_IDLE;
        endcase
    end
    assign run_busy_o = (state_q != S_IDLE);
    assign phase_o = (state_q == S_WAIT_C1);
    assign i0_level_o = i0_level_i[sweep_round_cnt_q];

    // Register the launch pulse. At this edge state/round counters update;
    // BANKs accept at the FOLLOWING edge, with the new phase and I0 already valid.
    // Never drive BANK start directly from the combinational transition event.
    assign phase_start_d = run_accept_w || phase0_done_w || next_sweep_w;

    // Zero-based counts advance only when continuing into the next sweep.
    // A fresh run restarts scheduling at stage zero without resetting node/RNG state.
    assign counters_en_w = run_accept_w || next_sweep_w;
    assign sweep_cnt_d = run_accept_w ? '0 :
        sweep_cnt_q + {{(NUM_SWEEP_WIDTH-1){1'b0}}, 1'b1};
    assign sweep_interval_cnt_d = (run_accept_w || interval_done_w) ? '0 :
        sweep_interval_cnt_q + {{(SWEEP_INTERVAL_WIDTH-1){1'b0}}, 1'b1};
    assign sweep_round_cnt_d = run_accept_w ? '0 :
        interval_done_w ? (round_last_w ? '0 :
            sweep_round_cnt_q + {{(SWEEP_ROUND_WIDTH-1){1'b0}}, 1'b1}) : sweep_round_cnt_q;
    // Preserve original clear/new-run priority over a simultaneous completion.
    assign run_done_d = (run_done_clr_pulse_i || run_accept_w) ? 1'b0 :
                        run_finish_w ? 1'b1 : run_done_o;
    // ------------------------------------------------------------
    // Register instances
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : state_ff
        if (!rst_n) state_q <= S_IDLE;
        else        state_q <= state_d;
    end

    dffr #(.WIDTH(1)) phase_start_ff (
        .clk(clk), .rst_n(rst_n), .d_i(phase_start_d), .q_o(phase_start_o)
    );

    dffre #(.WIDTH(NUM_SWEEP_WIDTH)) sweep_cnt_ff (
        .clk(clk), .rst_n(rst_n), .en_i(counters_en_w), .d_i(sweep_cnt_d), .q_o(sweep_cnt_q)
    );

    dffre #(.WIDTH(SWEEP_INTERVAL_WIDTH)) sweep_interval_cnt_ff (
        .clk(clk), .rst_n(rst_n), .en_i(counters_en_w),
        .d_i(sweep_interval_cnt_d), .q_o(sweep_interval_cnt_q)
    );

    dffre #(.WIDTH(SWEEP_ROUND_WIDTH)) sweep_round_cnt_ff (
        .clk(clk), .rst_n(rst_n), .en_i(counters_en_w),
        .d_i(sweep_round_cnt_d), .q_o(sweep_round_cnt_q)
    );

    dffr #(.WIDTH(1)) run_done_ff (
        .clk(clk), .rst_n(rst_n), .d_i(run_done_d), .q_o(run_done_o)
    );
endmodule
`endif
