`ifndef PBIT_CONTROL
`define PBIT_CONTROL
import pbit_pkg::*;
module pbit_control (
    input  logic clk,
    input  logic rst_n,

    // One-cycle start; busy starts are ignored. All BANKs start synchronously.
    input  logic phase_start_i,

    // Encoding 0..31 means N=1..32; captured only at idle start acceptance.
    input  logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,

    output logic phase_busy_o,
    output logic phase_done_o,
    output logic lfsr_en_o,
    output logic mac_en_o,
    output logic spin_sum_en_o,
    output logic majority_en_o
);
    typedef enum logic [1:0] {
        S_IDLE,
        S_CALC,
        S_DRAIN,
        S_COMMIT
    } state_e;

    state_e                         state_q, state_d;
    logic [NUM_MAJORITY_WIDTH-1:0]  trial_left_q, trial_left_d;
    logic                           trial_left_en;
    logic                           macsum_en, macsum_en_dly;
    logic                           spin_sum_en;
    logic                           majority_en;

    always @(*) begin
        case(state_q)
            S_IDLE: begin
                if(phase_start_i) state_d = S_CALC;
                else state_d = S_IDLE;
            end
            S_CALC: begin
                if(trial_left_q == '0) state_d = S_DRAIN;
                else state_d = S_CALC;
            end
            S_DRAIN: begin
                state_d = S_COMMIT;
            end
            S_COMMIT: begin
                state_d = S_IDLE;
            end
            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    // Zero executes the final MAC. Hold the counter at zero rather than wrap.
    assign trial_left_d   = (state_q == S_IDLE)? num_majority_i: trial_left_q - {{(NUM_MAJORITY_WIDTH-1){1'b0}}, 1'b1};
    assign trial_left_en  = ((state_q == S_IDLE) && phase_start_i) || ((state_q == S_CALC) && (trial_left_q != '0));
    assign macsum_en     = (state_q == S_CALC);
    // Delay MAC enable one cycle; collect the last sample in DRAIN before COMMIT.
    assign spin_sum_en   = macsum_en_dly;
    assign majority_en   = (state_q == S_COMMIT);
    // Advance from first MAC through commit (N+2 edges), excluding the start edge.
    assign phase_busy_o = (state_q != S_IDLE);
    assign lfsr_en_o = phase_busy_o;
    assign mac_en_o      = macsum_en;
    assign spin_sum_en_o = spin_sum_en;
    assign majority_en_o = majority_en;
    always_ff @(posedge clk or negedge rst_n) begin : state_ff
        if(~rst_n) begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    dffre #(.WIDTH(NUM_MAJORITY_WIDTH)
    ) trial_left_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(trial_left_en),
        .d_i(trial_left_d),
        .q_o(trial_left_q)
    );

    dffr #(.WIDTH(1)
    ) macsum_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(macsum_en),
        .q_o(macsum_en_dly)
    );
    // Registered completion becomes valid after the node commit edge.
    dffr #(.WIDTH(1)) phase_done_ff (
        .clk(clk), .rst_n(rst_n), .d_i(majority_en), .q_o(phase_done_o)
    );
endmodule
`endif
