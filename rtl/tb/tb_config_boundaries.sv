`timescale 1ns/1ps
import pbit_pkg::*;

// Count-encoding, anneal-stage and exact phase-cycle regression.
module tb_config_boundaries;
    localparam realtime CLK_PERIOD = 1s / real'(CLK_FREQ_HZ);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic uart_mode = 1'b0;
    logic rx = 1'b1;
    logic wr_en = 1'b0;
    logic rd_en = 1'b0;
    logic [15:0] addr = '0;
    logic [31:0] wdata = '0;
    wire tx;
    wire [31:0] rdata;
    wire access_error, cfg_busy, run_busy, run_done;
    wire run_accept, sweep_done, phase_start, phase;
    wire [I0_LEVEL_WIDTH-1:0] i0;
    wire [N_SPIN-1:0] spins;
    wire [BANK_ROWS*BANK_COLS-1:0] bank_done;

    longint unsigned cycle = 0;
    longint unsigned start_cycle = 0;
    longint unsigned final_cycle = 0;
    integer phase_count = 0;
    integer sweep_count = 0;
    integer expected_i0 [0:7];
    integer expected_threshold = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    chimera_problem_harness dut (.*);

    task automatic bus_access(
        input bit write_access,
        input logic [15:0] address,
        input logic [31:0] value,
        input bit expected_error,
        output logic [31:0] result
    );
        @(negedge clk);
        addr = address;
        wdata = value;
        wr_en = write_access;
        rd_en = !write_access;
        @(posedge clk);
        #(CLK_PERIOD/4);
        if (access_error !== expected_error)
            $fatal(1, "Access error address=%h actual=%b expected=%b", address,
                   access_error, expected_error);
        result = rdata;
        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
    endtask

    task automatic wr(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        bus_access(1'b1, address, value, 1'b0, ignored);
    endtask

    task automatic check(input logic [15:0] address, input logic [31:0] expected);
        logic [31:0] actual;
        bus_access(1'b0, address, 32'd0, 1'b0, actual);
        if (actual !== expected)
            $fatal(1, "Readback address=%h actual=%h expected=%h", address, actual, expected);
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);
        phase_count = 0;
        sweep_count = 0;
        start_cycle = 0;
        final_cycle = 0;
    endtask

    task automatic run_case(
        input integer actual_sweeps,
        input integer actual_majority,
        input bit first_stage_two_sweeps
    );
        logic [31:0] global_cfg;
        logic [31:0] status;
        integer waited;
        longint unsigned expected_cycles;
        integer code;

        reset_dut();
        wr(A_I0_LEVEL0, 32'h0f0b_0703);
        wr(A_SWEEP_INTERVAL0, first_stage_two_sweeps ? 32'h0000_0001 : 32'd0);
        code = actual_majority - 1;
        expected_threshold = (code >> 1) + 1 + (((code & 1) != 0) && ((code & 2) != 0));
        for (int idx = 0; idx < 8; idx++) expected_i0[idx] = 0;
        if (first_stage_two_sweeps) begin
            expected_i0[0] = 3;
            expected_i0[1] = 3;
            expected_i0[2] = 7;
            expected_i0[3] = 11;
            expected_i0[4] = 15;
        end else begin
            expected_i0[0] = 3;
            expected_i0[1] = 7;
            expected_i0[2] = 11;
            expected_i0[3] = 15;
        end
        global_cfg = ((actual_majority-1) << NUM_MAJORITY_LSB) | (actual_sweeps-1);
        wr(A_GLOBAL_CFG, global_cfg);
        check(A_GLOBAL_CFG, global_cfg);
        wr(A_GLOBAL_CTRL, 1 << CFG_DONE_SET_LSB);
        wr(A_GLOBAL_CTRL, 1 << RUN_START_LSB);

        waited = 0;
        while (!run_done) begin
            @(negedge clk);
            waited++;
            if (waited > actual_sweeps*2*(actual_majority+12)+100)
                $fatal(1, "Run timeout sweeps=%0d majority=%0d", actual_sweeps, actual_majority);
        end
        @(negedge clk);
        expected_cycles = actual_sweeps * 2 * (actual_majority + 4);
        if (run_busy || sweep_count != actual_sweeps || phase_count != 2*actual_sweeps)
            $fatal(1, "Count mismatch sweeps=%0d/%0d phases=%0d/%0d busy=%b",
                   sweep_count, actual_sweeps, phase_count, 2*actual_sweeps, run_busy);
        if (final_cycle != expected_cycles)
            $fatal(1, "Cycle mismatch sweeps=%0d majority=%0d actual=%0d expected=%0d",
                   actual_sweeps, actual_majority, final_cycle, expected_cycles);
        bus_access(1'b0, A_GLOBAL_STATUS, 32'd0, 1'b0, status);
        if (!status[CFG_DONE_LSB] || !status[RUN_DONE_LSB] || status[RUN_BUSY_LSB] || status[ERROR_LSB])
            $fatal(1, "Boundary run status=%h", status);
        $display("[CONFIG_BOUNDARY] sweeps=%0d majority=%0d cycles=%0d threshold=%0d PASS",
                 actual_sweeps, actual_majority, final_cycle, expected_threshold);
    endtask

    always @(posedge clk) begin : MONITOR
        cycle++;
        if (rst_n && run_accept) start_cycle = cycle;
        if (rst_n && phase_start) begin
            phase_count++;
            #(CLK_PERIOD/4);
            if (dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.vote_threshold_q !==
                NUM_MAJORITY_WIDTH'(expected_threshold))
                $fatal(1, "Vote threshold actual=%0d expected=%0d",
                       dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.vote_threshold_q,
                       expected_threshold);
        end
        if (rst_n && (|bank_done) && !(&bank_done))
            $fatal(1, "Bank completion mismatch: %h", bank_done);
        if (rst_n && sweep_done) begin
            if (i0 !== I0_LEVEL_WIDTH'(expected_i0[sweep_count]))
                $fatal(1, "Schedule mismatch sweep=%0d i0=%0d expected=%0d",
                       sweep_count+1, i0, expected_i0[sweep_count]);
            sweep_count++;
            final_cycle = cycle - start_cycle;
        end
    end

    initial begin : TEST
        run_case(1, 1, 1'b0);
        run_case(2, 2, 1'b0);
        run_case(4, 31, 1'b0);
        run_case(4, 32, 1'b0);
        run_case(5, 5, 1'b1);

        // Maximum encoded fields are checked without attempting 2^24 sweeps.
        reset_dut();
        wr(A_GLOBAL_CFG, 32'hffff_ffff);
        check(A_GLOBAL_CFG, 32'h1fff_ffff);
        wr(A_I0_LEVEL0, 32'hffff_ffff);
        check(A_I0_LEVEL0, 32'h1f1f_1f1f);
        wr(A_SWEEP_INTERVAL0, 32'hffff_ffff);
        check(A_SWEEP_INTERVAL0, 32'hffff_ffff);
        check(A_ERROR_STATUS, 32'd0);

        $display("[TB_CONFIG_BOUNDARIES] PASS");
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "TB_CONFIG_BOUNDARIES timeout");
    end
endmodule
