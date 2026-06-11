`timescale 1ns / 1ps

module phase_ctrl_4color #(
    parameter integer NUM_SWEEPS = 50
)(
    input  wire clk,
    input  wire rst_n,

    input  wire cfg_done_i,
    input  wire run_start_pulse_i,

    input  wire all_done_c0_i,
    input  wire all_done_c1_i,
    input  wire all_done_c2_i,
    input  wire all_done_c3_i,

    output wire phase_start_c0_o,
    output wire phase_start_c1_o,
    output wire phase_start_c2_o,
    output wire phase_start_c3_o,

    output reg  [3:0]  i0_level_o,
    output reg  [31:0] sweep_cnt_o,

    output reg         sweep_done_pulse_o,
    output reg         run_busy_o,
    output reg         run_done_o
);

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------

    localparam S_IDLE      = 5'd0;

    localparam S_START_C0  = 5'd1;
    localparam S_GAP_C0    = 5'd2;
    localparam S_WAIT_C0   = 5'd3;

    localparam S_START_C1  = 5'd4;
    localparam S_GAP_C1    = 5'd5;
    localparam S_WAIT_C1   = 5'd6;

    localparam S_START_C2  = 5'd7;
    localparam S_GAP_C2    = 5'd8;
    localparam S_WAIT_C2   = 5'd9;

    localparam S_START_C3  = 5'd10;
    localparam S_GAP_C3    = 5'd11;
    localparam S_WAIT_C3   = 5'd12;

    localparam S_DONE      = 5'd13;

    reg [4:0] state_q;

    // ------------------------------------------------------------
    // Phase start pulses
    // Each is high for exactly one clock cycle.
    // ------------------------------------------------------------

    assign phase_start_c0_o = (state_q == S_START_C0);
    assign phase_start_c1_o = (state_q == S_START_C1);
    assign phase_start_c2_o = (state_q == S_START_C2);
    assign phase_start_c3_o = (state_q == S_START_C3);

    // ------------------------------------------------------------
    // Fast annealing schedule
    //
    // Original:
    //   level = floor((15*sweep + (NUM_SWEEPS-1)/2) / (NUM_SWEEPS-1))
    //
    // Optimized:
    //   Precompute the sweep threshold at which each level starts.
    //   Runtime only compares sweep_cnt against constants.
    //
    // Threshold for entering level L:
    //   smallest sweep such that:
    //       floor((15*sweep + denom/2) / denom) >= L
    //
    //   where denom = NUM_SWEEPS - 1.
    //
    // This function is used only for localparams, so division is
    // elaboration-time constant computation, not hardware division.
    // ------------------------------------------------------------

    function integer level_start_threshold;
        input integer level;
        integer denom;
        integer numerator;
        integer threshold;
        begin
            if (NUM_SWEEPS <= 1) begin
                level_start_threshold = 0;
            end else begin
                denom = NUM_SWEEPS - 1;

                // ceil((level*denom - denom/2) / 15)
                numerator = level * denom - (denom / 2);

                if (numerator <= 0) begin
                    threshold = 0;
                end else begin
                    threshold = (numerator + 14) / 15;
                end

                if (threshold < 0) begin
                    level_start_threshold = 0;
                end else if (threshold > (NUM_SWEEPS - 1)) begin
                    level_start_threshold = NUM_SWEEPS - 1;
                end else begin
                    level_start_threshold = threshold;
                end
            end
        end
    endfunction

    localparam integer LTH_01 = level_start_threshold(1);
    localparam integer LTH_02 = level_start_threshold(2);
    localparam integer LTH_03 = level_start_threshold(3);
    localparam integer LTH_04 = level_start_threshold(4);
    localparam integer LTH_05 = level_start_threshold(5);
    localparam integer LTH_06 = level_start_threshold(6);
    localparam integer LTH_07 = level_start_threshold(7);
    localparam integer LTH_08 = level_start_threshold(8);
    localparam integer LTH_09 = level_start_threshold(9);
    localparam integer LTH_10 = level_start_threshold(10);
    localparam integer LTH_11 = level_start_threshold(11);
    localparam integer LTH_12 = level_start_threshold(12);
    localparam integer LTH_13 = level_start_threshold(13);
    localparam integer LTH_14 = level_start_threshold(14);
    localparam integer LTH_15 = level_start_threshold(15);

    localparam [3:0] INIT_I0_LEVEL =
        (NUM_SWEEPS <= 1) ? 4'd15 : 4'd0;

    function [3:0] calc_i0_level_fast;
        input [31:0] sweep_idx;
        begin
            if (NUM_SWEEPS <= 1) begin
                calc_i0_level_fast = 4'd15;
            end else if (sweep_idx < LTH_01) begin
                calc_i0_level_fast = 4'd0;
            end else if (sweep_idx < LTH_02) begin
                calc_i0_level_fast = 4'd1;
            end else if (sweep_idx < LTH_03) begin
                calc_i0_level_fast = 4'd2;
            end else if (sweep_idx < LTH_04) begin
                calc_i0_level_fast = 4'd3;
            end else if (sweep_idx < LTH_05) begin
                calc_i0_level_fast = 4'd4;
            end else if (sweep_idx < LTH_06) begin
                calc_i0_level_fast = 4'd5;
            end else if (sweep_idx < LTH_07) begin
                calc_i0_level_fast = 4'd6;
            end else if (sweep_idx < LTH_08) begin
                calc_i0_level_fast = 4'd7;
            end else if (sweep_idx < LTH_09) begin
                calc_i0_level_fast = 4'd8;
            end else if (sweep_idx < LTH_10) begin
                calc_i0_level_fast = 4'd9;
            end else if (sweep_idx < LTH_11) begin
                calc_i0_level_fast = 4'd10;
            end else if (sweep_idx < LTH_12) begin
                calc_i0_level_fast = 4'd11;
            end else if (sweep_idx < LTH_13) begin
                calc_i0_level_fast = 4'd12;
            end else if (sweep_idx < LTH_14) begin
                calc_i0_level_fast = 4'd13;
            end else if (sweep_idx < LTH_15) begin
                calc_i0_level_fast = 4'd14;
            end else begin
                calc_i0_level_fast = 4'd15;
            end
        end
    endfunction

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= S_IDLE;

            i0_level_o         <= 4'd0;
            sweep_cnt_o        <= 32'd0;

            sweep_done_pulse_o <= 1'b0;
            run_busy_o         <= 1'b0;
            run_done_o         <= 1'b0;
        end else begin
            sweep_done_pulse_o <= 1'b0;

            case (state_q)

                // ------------------------------------------------
                // Idle
                // ------------------------------------------------

                S_IDLE: begin
                    run_busy_o  <= 1'b0;
                    run_done_o  <= 1'b0;
                    sweep_cnt_o <= 32'd0;
                    i0_level_o  <= 4'd0;

                    if (cfg_done_i && run_start_pulse_i) begin
                        run_busy_o  <= 1'b1;
                        run_done_o  <= 1'b0;

                        sweep_cnt_o <= 32'd0;
                        i0_level_o  <= INIT_I0_LEVEL;

                        state_q     <= S_START_C0;
                    end
                end

                // ------------------------------------------------
                // Color 0
                // ------------------------------------------------

                S_START_C0: begin
                    state_q <= S_GAP_C0;
                end

                S_GAP_C0: begin
                    state_q <= S_WAIT_C0;
                end

                S_WAIT_C0: begin
                    if (all_done_c0_i) begin
                        state_q <= S_START_C1;
                    end
                end

                // ------------------------------------------------
                // Color 1
                // ------------------------------------------------

                S_START_C1: begin
                    state_q <= S_GAP_C1;
                end

                S_GAP_C1: begin
                    state_q <= S_WAIT_C1;
                end

                S_WAIT_C1: begin
                    if (all_done_c1_i) begin
                        state_q <= S_START_C2;
                    end
                end

                // ------------------------------------------------
                // Color 2
                // ------------------------------------------------

                S_START_C2: begin
                    state_q <= S_GAP_C2;
                end

                S_GAP_C2: begin
                    state_q <= S_WAIT_C2;
                end

                S_WAIT_C2: begin
                    if (all_done_c2_i) begin
                        state_q <= S_START_C3;
                    end
                end

                // ------------------------------------------------
                // Color 3
                // ------------------------------------------------

                S_START_C3: begin
                    state_q <= S_GAP_C3;
                end

                S_GAP_C3: begin
                    state_q <= S_WAIT_C3;
                end

                S_WAIT_C3: begin
                    if (all_done_c3_i) begin
                        sweep_done_pulse_o <= 1'b1;

                        if (sweep_cnt_o == NUM_SWEEPS - 1) begin
                            run_busy_o <= 1'b0;
                            run_done_o <= 1'b1;
                            state_q    <= S_DONE;
                        end else begin
                            sweep_cnt_o <= sweep_cnt_o + 32'd1;

                            // No division here. Only constant comparisons.
                            i0_level_o  <= calc_i0_level_fast(sweep_cnt_o + 32'd1);

                            state_q     <= S_START_C0;
                        end
                    end
                end

                // ------------------------------------------------
                // Done
                // ------------------------------------------------

                S_DONE: begin
                    run_busy_o <= 1'b0;
                    run_done_o <= 1'b1;

                    // Allow re-run without reconfiguration if cfg_done_i remains high.
                    if (cfg_done_i && run_start_pulse_i) begin
                        run_done_o  <= 1'b0;
                        run_busy_o  <= 1'b1;

                        sweep_cnt_o <= 32'd0;
                        i0_level_o  <= INIT_I0_LEVEL;

                        state_q     <= S_START_C0;
                    end
                end

                default: begin
                    state_q <= S_IDLE;
                end

            endcase
        end
    end

endmodule
