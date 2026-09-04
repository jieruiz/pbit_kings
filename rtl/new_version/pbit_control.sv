`ifndef PBIT_CONTROL
`define PBIT_CONTROL
import pbit_pkg::*;
module pbit_control (
    input  logic clk,
    input  logic rst_n,
    input  logic soft_rstn_i,

    input  logic phase_start_i,

    input  logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,

    output logic mac_en_o,
    output logic spin_sum_en_o,
    output logic majority_en_o
);
    typedef enum logic [1:0] {
        S_IDLE,
        S_CACL,
        S_SUM,
        S_MAJORITY
    } state_e;

    state_e                         state_q, state_d;   
    logic [NUM_MAJORITY_WIDTH-1:0]  trial_idx_q, trial_idx_d;
    logic                           trial_idx_en;
    logic                           macsum_en, macsum_en_dly;
    logic                           spin_sum_en;
    logic                           majority_en;

    always @(*) begin
        case(state_q)
            S_IDLE: begin
                if(phase_start_i) state_d = S_CACL;
                else state_d = S_IDLE;
            end
            S_CACL: begin
                if(trial_idx_q == num_majority_i) state_d = S_SUM;
                else state_d = S_CACL;
            end
            S_SUM: begin
                state_d = S_MAJORITY;
            end
            S_MAJORITY: begin
                state_d = S_IDLE;
            end
            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    assign trial_idx_d   = (state_q == S_IDLE)? {NUM_MAJORITY_WIDTH{1'b0}}: trial_idx_q + {{(NUM_MAJORITY_WIDTH-1){1'b0}}, 1'b1};
    assign trial_idx_en  = (state_q == S_IDLE) || (state_q == S_CACL);
    assign macsum_en     = (state_q == S_CACL);
    assign spin_sum_en   = (state_q == S_MAJORITY) || macsum_en_dly;
    assign majority_en   = (state_q == S_MAJORITY);
    assign mac_en_o      = macsum_en;
    assign spin_sum_en_o = spin_sum_en;
    assign majority_en_o = majority_en;
    always_ff @(posedge clk or negedge rst_n) begin : state_ff
        if(~rst_n) begin
            state_q <= S_IDLE;
        end else if(~soft_rstn_i) begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    dffsre #(.WIDTH(NUM_MAJORITY_WIDTH)
    ) trial_idx_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .en_i(trial_idx_en),
        .d_i(trial_idx_d),
        .q_o(trial_idx_q)
    );

    dffsr #(.WIDTH(1)
    ) macsum_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .d_i(macsum_en),
        .q_o(macsum_en_dly)
    );
endmodule
`endif