`timescale 1ns/1ps
import pbit_pkg::*;

// Directed regression for command conflicts, sticky errors and reset recovery.
module tb_error_paths;
    localparam int CPB = CLK_FREQ_HZ / BAUD_RATE;
    localparam realtime CLK_PERIOD = 1s / real'(CLK_FREQ_HZ);
    localparam realtime BIT_TIME = CPB * CLK_PERIOD;

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
            $fatal(1, "Bus error address=%h actual=%b expected=%b", address,
                   access_error, expected_error);
        result = rdata;
        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
    endtask

    task automatic bus_write(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        bus_access(1'b1, address, value, 1'b0, ignored);
    endtask

    task automatic bus_write_error(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        bus_access(1'b1, address, value, 1'b1, ignored);
    endtask

    task automatic bus_read(input logic [15:0] address, output logic [31:0] value);
        bus_access(1'b0, address, 32'd0, 1'b0, value);
    endtask

    task automatic bus_check(input logic [15:0] address, input logic [31:0] expected);
        logic [31:0] actual;
        bus_read(address, actual);
        if (actual !== expected)
            $fatal(1, "Readback address=%h actual=%h expected=%h", address, actual, expected);
    endtask

    task automatic clear_errors;
        bus_write(A_ERROR_STATUS, 32'hffff_ffff);
        bus_check(A_ERROR_STATUS, 32'd0);
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 1'b0;
        uart_mode = 1'b0;
        rx = 1'b1;
        wr_en = 1'b0;
        rd_en = 1'b0;
        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);
    endtask

    task automatic wait_cfg_idle;
        integer waited;
        waited = 0;
        while (cfg_busy) begin
            @(negedge clk);
            waited++;
            if (waited > 100) $fatal(1, "CFG_BUSY did not clear");
        end
    endtask

    task automatic wait_run_busy;
        integer waited;
        waited = 0;
        while (!run_busy) begin
            @(negedge clk);
            waited++;
            if (waited > 50) $fatal(1, "RUN_BUSY did not assert");
        end
    endtask

    task automatic wait_run_done;
        integer waited;
        waited = 0;
        while (!run_done) begin
            @(negedge clk);
            waited++;
            if (waited > 2000) $fatal(1, "RUN_DONE timeout");
        end
    endtask

    task automatic send_byte(input logic [7:0] value);
        rx = 1'b0;
        #(BIT_TIME);
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            rx = value[bit_idx];
            #(BIT_TIME);
        end
        rx = 1'b1;
        #(BIT_TIME);
    endtask

    task automatic receive_byte(output logic [7:0] value);
        @(negedge tx);
        #(BIT_TIME/2);
        if (tx !== 1'b0) $fatal(1, "UART error-test start bit");
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            #(BIT_TIME);
            value[bit_idx] = tx;
        end
        #(BIT_TIME);
        if (tx !== 1'b1) $fatal(1, "UART error-test stop bit");
    endtask

    task automatic uart_exchange(
        input logic [7:0] opcode,
        input logic [15:0] address,
        input logic [31:0] value,
        input logic [7:0] expected_status
    );
        logic [55:0] request;
        logic [55:0] response;
        logic [7:0] received;
        request = {opcode, address, value};
        response = '0;
        fork
            begin
                for (int byte_idx = 6; byte_idx >= 0; byte_idx--)
                    send_byte(request[byte_idx*8 +: 8]);
            end
            begin
                for (int byte_idx = 6; byte_idx >= 0; byte_idx--) begin
                    receive_byte(received);
                    response[byte_idx*8 +: 8] = received;
                end
            end
        join
        if (response[55:48] !== expected_status || response[47:32] !== address)
            $fatal(1, "UART error response request=%h response=%h", request, response);
        #(2*BIT_TIME);
    endtask

    initial begin : TEST
        logic [31:0] expected_errors;
        logic [31:0] status;

        // RUN is rejected before CFG_DONE.
        reset_dut();
        bus_write_error(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        bus_check(A_ERROR_STATUS, 1 << RUN_WITHOUT_CFG_DONE_LSB);
        clear_errors();

        // A second command while an array request is outstanding must not replace it.
        bus_write(A_UNIT_TARGET, 32'd0);
        bus_write(A_NODE_TARGET, 32'd0);
        bus_write(A_NODE_CFG, 32'h0000_0101);
        bus_write(A_NODE_CMD, 1 << APPLY_CFG_LSB);
        if (!cfg_busy) $fatal(1, "Expected CFG_BUSY after NODE command");
        bus_write_error(A_SEED_CMD, 1 << APPLY_SEED_LSB);
        wait_cfg_idle();
        bus_check(A_ERROR_STATUS, 1 << CFG_CMD_WHILE_BUSY_LSB);
        clear_errors();
        bus_write(A_NODE_CMD, 1 << READBACK_CFG_LSB);
        wait_cfg_idle();
        bus_check(A_NODE_RDATA_CFG, 32'h0000_0001);

        // RUN_START is also rejected while the configuration pipe is busy.
        bus_write(A_GLOBAL_CTRL, 1 << CFG_DONE_SET_LSB);
        bus_write(A_NODE_CMD, 1 << APPLY_CFG_LSB);
        if (!cfg_busy) $fatal(1, "Expected CFG_BUSY before RUN conflict");
        bus_write_error(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        wait_cfg_idle();
        bus_check(A_ERROR_STATUS, 1 << RUN_WHILE_CFG_BUSY_LSB);
        clear_errors();

        // Runtime writes must be rejected independently and preserve all parameters.
        bus_write(A_GLOBAL_CFG, 32'h1f00_0007); // 8 sweeps, majority 32.
        bus_write(A_I0_LEVEL0, 32'h0403_0201);
        bus_write(A_SWEEP_INTERVAL0, 32'h0001_0001);
        bus_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        wait_run_busy();
        bus_write_error(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        bus_write_error(A_GLOBAL_CFG, 32'h0000_0000);
        bus_write_error(A_I0_LEVEL0, 32'h1f1f_1f1f);
        bus_write_error(A_SWEEP_INTERVAL0, 32'hffff_ffff);
        bus_write_error(A_NODE_CMD, 1 << APPLY_CFG_LSB);
        bus_write_error(A_SEED_CMD, 1 << APPLY_SEED_LSB);
        bus_write_error(A_EDGE_CMD, 1 << APPLY_EDGE_LSB);
        expected_errors = (1 << RUN_WHEN_BUSY_LSB) |
                          (1 << GLOBAL_CFG_WHILE_RUN_LSB) |
                          (1 << I0_CFG_WHILE_RUN_LSB) |
                          (1 << SWEEP_CFG_WHILE_RUN_LSB) |
                          (1 << NODE_CFG_WHILE_RUN_LSB) |
                          (1 << SEED_CFG_WHILE_RUN_LSB) |
                          (1 << EDGE_CFG_WHILE_RUN_LSB);
        bus_check(A_ERROR_STATUS, expected_errors);
        bus_check(A_GLOBAL_CFG, 32'h1f00_0007);
        bus_check(A_I0_LEVEL0, 32'h0403_0201);
        bus_check(A_SWEEP_INTERVAL0, 32'h0001_0001);
        wait_run_done();
        clear_errors();

        // Reset discards an outstanding array request and permits clean reconfiguration.
        bus_write(A_NODE_CMD, 1 << APPLY_CFG_LSB);
        if (!cfg_busy) $fatal(1, "Expected CFG_BUSY before reset interruption");
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);
        if (cfg_busy || run_busy || run_done || (^spins) === 1'bx)
            $fatal(1, "Reset recovery busy=%b run=%b done=%b", cfg_busy, run_busy, run_done);
        bus_check(A_GLOBAL_STATUS, 32'd0);
        bus_check(A_ERROR_STATUS, 32'd0);

        // Illegal opcode traverses the real UART RX and sets the sticky frame error.
        uart_mode = 1'b1;
        uart_exchange(8'h7f, A_GLOBAL_STATUS, 32'd0, 8'h01);
        uart_mode = 1'b0;
        bus_check(A_ERROR_STATUS, 1 << UART_FRAME_ERR_LSB);
        clear_errors();

        // Force only the master's host-busy predicate, then send a complete real frame.
        // This deterministically exercises ST_BUSY plus the UART_OVERFLOW sticky event.
        uart_mode = 1'b1;
        force dut.u_uart.uart_busy_w = 1'b1;
        uart_exchange(8'h02, A_GLOBAL_STATUS, 32'd0, 8'h03);
        release dut.u_uart.uart_busy_w;
        uart_mode = 1'b0;
        bus_check(A_ERROR_STATUS, 1 << UART_OVERFLOW_LSB);
        clear_errors();

        // Two complete runs may execute without a global reset when RUN_DONE is cleared.
        bus_write(A_GLOBAL_CFG, 32'd0); // One sweep, majority one.
        bus_write(A_GLOBAL_CTRL, 1 << CFG_DONE_SET_LSB);
        bus_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        wait_run_done();
        bus_write(A_GLOBAL_CTRL, 1 << RUN_DONE_CLEAR_LSB);
        bus_read(A_GLOBAL_STATUS, status);
        if (status !== (1 << CFG_DONE_LSB)) $fatal(1, "First RUN clear status=%h", status);
        bus_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        wait_run_done();
        bus_read(A_GLOBAL_STATUS, status);
        if (!status[RUN_DONE_LSB] || status[RUN_BUSY_LSB] || status[ERROR_LSB])
            $fatal(1, "Back-to-back RUN status=%h", status);

        // An asynchronous reset during a long run returns every controller to idle.
        bus_write(A_GLOBAL_CTRL, 1 << RUN_DONE_CLEAR_LSB);
        bus_write(A_GLOBAL_CFG, 32'h1f00_0007);
        bus_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        wait_run_busy();
        repeat (10) @(negedge clk);
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);
        if (cfg_busy || run_busy || run_done || (^spins) === 1'bx)
            $fatal(1, "Mid-run reset recovery busy=%b run=%b done=%b", cfg_busy, run_busy, run_done);
        bus_check(A_GLOBAL_STATUS, 32'd0);
        bus_check(A_ERROR_STATUS, 32'd0);

        $display("[TB_ERROR_PATHS] PASS");
        $finish;
    end

    initial begin
        #5ms;
        $fatal(1, "TB_ERROR_PATHS timeout");
    end
endmodule
