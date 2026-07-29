`ifndef PHASE_CTRL_4COLOR
`define PHASE_CTRL_4COLOR
import pbit_pkg::*;
module phase_ctrl_4color (
    input  logic clk,
    input  logic rst_n,
    input  logic glb_soft_rstn_i,

    input  logic cfg_done_i,
    input  logic run_start_pulse_i,
    input  logic [NUM_SWEEP_WIDTH-1:0] num_sweeps_i,

    input  wire [I0_LEVEL_WIDTH-1:0] i0_level_i[SWEEP_ROUND_NUM],

    input  wire [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_i[SWEEP_ROUND_NUM],

    input  logic all_done_c0_i,
    input  logic all_done_c1_i,
    input  logic all_done_c2_i,
    input  logic all_done_c3_i,

    output logic phase_start_c0_o,
    output logic phase_start_c1_o,
    output logic phase_start_c2_o,
    output logic phase_start_c3_o,

    output logic  [I0_LEVEL_WIDTH-1:0]  i0_level_o,

    output logic         run_busy_o,
    output logic         run_done_o
);

    typedef enum logic [2:0] { 
        S_IDLE    = 3'd0,
        S_WAIT_C0 = 3'd1,
        S_WAIT_C1 = 3'd2,
        S_WAIT_C2 = 3'd3,
        S_WAIT_C3 = 3'd4
    } state_e;

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------
    state_e state_q, state_d;

    // ------------------------------------------------------------
    // sweep counter
    // ------------------------------------------------------------
    logic [NUM_SWEEP_WIDTH-1:0] sweep_cnt_q, sweep_cnt_d;
    logic sweep_cnt_en;

    // ------------------------------------------------------------
    // sweep interval counter
    // ------------------------------------------------------------
    logic [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_cnt_q, sweep_interval_cnt_d;
    logic sweep_interval_cnt_en;

    // ------------------------------------------------------------
    // sweep round counter
    // ------------------------------------------------------------
    logic [SWEEP_ROUND_WIDTH-1:0] sweep_round_cnt_q, sweep_round_cnt_d;
    logic sweep_round_cnt_en;
    assign i0_level_o = i0_level_i[sweep_round_cnt_q];

    // ------------------------------------------------------------
    // run_busy
    // ------------------------------------------------------------
    logic run_busy_q, run_busy_d;

    // ------------------------------------------------------------
    // run_done
    // ------------------------------------------------------------
    logic run_done_q, run_done_d;

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------
    always @(*) begin
        case(state_q)
            S_IDLE: begin
                if(cfg_done_i && run_start_pulse_i) begin
                    state_d = S_WAIT_C0;
                end else begin
                    state_d = S_IDLE;
                end
            end

            S_WAIT_C0: begin
                if (all_done_c0_i) begin
                    state_d = S_WAIT_C1;
                end else begin
                    state_d = S_WAIT_C0;
                end
            end

            S_WAIT_C1: begin
                if (all_done_c1_i) begin
                    state_d = S_WAIT_C2;
                end else begin
                    state_d = S_WAIT_C1;
                end
            end

            S_WAIT_C2: begin
                if (all_done_c2_i) begin
                    state_d = S_WAIT_C3;
                end else begin
                    state_d = S_WAIT_C2;
                end
            end

            S_WAIT_C3: begin
                if (all_done_c3_i) begin
                    if (sweep_cnt_q == (num_sweeps_i - 1)) begin
                        state_d = S_IDLE;
                    end else begin
                        state_d = S_WAIT_C0;
                    end
                end else begin
                    state_d = S_WAIT_C3;
                end
            end

            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // phase start pulse
    // ------------------------------------------------------------
    assign phase_start_c0_o = (state_q == S_IDLE) && (state_d == S_WAIT_C0);
    assign phase_start_c1_o = (state_q == S_WAIT_C0) && (state_d == S_WAIT_C1);
    assign phase_start_c2_o = (state_q == S_WAIT_C1) && (state_d == S_WAIT_C2);
    assign phase_start_c3_o = (state_q == S_WAIT_C2) && (state_d == S_WAIT_C3);
    
    // ------------------------------------------------------------
    // sweep counter
    // ------------------------------------------------------------
    assign sweep_cnt_d  = (state_q == S_IDLE)? {NUM_SWEEP_WIDTH{1'b0}}:
                          (state_q == S_WAIT_C3)? sweep_cnt_q + {{(NUM_SWEEP_WIDTH-1){1'b0}}, 1'b1}:
                                                  sweep_cnt_q;
    assign sweep_cnt_en = ((state_q == S_IDLE) && (state_d == S_WAIT_C0)) || ((state_q == S_WAIT_C3) && (state_d == S_WAIT_C0));
    
    
    // ------------------------------------------------------------
    // sweep interval counter
    // ------------------------------------------------------------
    assign sweep_interval_cnt_d  = (state_q == S_IDLE)? {SWEEP_INTERVAL_WIDTH{1'b0}}:
                                   (state_q == S_WAIT_C3)? (sweep_interval_cnt_q == (sweep_interval_i[sweep_round_cnt_q] - 1))? {SWEEP_INTERVAL_WIDTH{1'b0}}:
                                                                                                                                sweep_interval_cnt_q + {{(SWEEP_INTERVAL_WIDTH-1){1'b0}}, 1'b1}:
                                                           sweep_interval_cnt_q;
    assign sweep_interval_cnt_en = ((state_q == S_IDLE) && (state_d == S_WAIT_C0)) || ((state_q == S_WAIT_C3) && (state_d == S_WAIT_C0));

    // ------------------------------------------------------------
    // sweep round counter
    // ------------------------------------------------------------
    assign sweep_round_cnt_d  = (state_q == S_IDLE)? {SWEEP_ROUND_WIDTH{1'b0}}:
                                (state_q == S_WAIT_C3)? (sweep_interval_cnt_q == (sweep_interval_i[sweep_round_cnt_q] - 1))? |sweep_interval_i[sweep_round_cnt_q+1]? sweep_round_cnt_q + {{(SWEEP_ROUND_WIDTH-1){1'b0}}, 1'b1}:
                                                                                                                                                                     {SWEEP_ROUND_WIDTH{1'b0}}:
                                                                                                                             sweep_round_cnt_q:
                                                        sweep_round_cnt_q;
    assign sweep_round_cnt_en = ((state_q == S_IDLE) && (state_d == S_WAIT_C0)) || ((state_q == S_WAIT_C3) && (state_d == S_WAIT_C0));

    // ------------------------------------------------------------
    // run_busy
    // ------------------------------------------------------------
    assign run_busy_d = ((state_q == S_IDLE) && (state_q == S_WAIT_C0))? 1'b1:
                        ((state_q == S_WAIT_C3) && (state_d == S_IDLE))? 1'b0:
                        run_busy_q;
    assign run_busy_o = run_busy_q;
    
    // ------------------------------------------------------------
    // run_done
    // ------------------------------------------------------------
    assign run_done_d = ((state_q == S_IDLE) && (state_d == S_WAIT_C0))? 1'b0:
                        ((state_q == S_WAIT_C3) && (state_d == S_IDLE))? 1'b1:
                        run_done_q;
    assign run_done_o = run_done_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            state_q <= S_IDLE;
        end else if(~glb_soft_rstn_i) begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    dffe #(.WIDTH(NUM_SWEEP_WIDTH)
    ) sweep_cnt_ff (
        .clk(clk),
        .en_i(sweep_cnt_en),
        .d_i(sweep_cnt_d),
        .q_o(sweep_cnt_q)
    );

    dffe #(.WIDTH(SWEEP_INTERVAL_WIDTH)
    ) sweep_interval_cnt_ff (
        .clk(clk),
        .en_i(sweep_interval_cnt_en),
        .d_i(sweep_interval_cnt_d),
        .q_o(sweep_interval_cnt_q)
    );

    dffe #(.WIDTH(SWEEP_ROUND_WIDTH)
    ) sweep_round_cnt_ff (
        .clk(clk),
        .en_i(sweep_round_cnt_en),
        .d_i(sweep_round_cnt_d),
        .q_o(sweep_round_cnt_q)
    );

    dffsr #(
        .WIDTH      (1)
    ) run_busy_ff (
        .clk        (clk),
        .rst_n      (rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i        (run_busy_d),
        .q_o        (run_busy_q)
    );

    dffsr #(
        .WIDTH      (1)
    ) run_done_ff (
        .clk        (clk),
        .rst_n      (rst_n),
        .soft_rstn_i(glb_soft_rstn_i),
        .d_i        (run_done_d),
        .q_o        (run_done_q)
    );
endmodule
`endif