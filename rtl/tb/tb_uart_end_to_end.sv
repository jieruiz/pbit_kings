`timescale 1ns/1ps
import pbit_pkg::*;

// Production-UART smoke test from serialized configuration through RUN/snapshot.
module tb_uart_end_to_end;
    localparam int CPB = CLK_FREQ_HZ / BAUD_RATE;
    localparam realtime CLK_PERIOD = 1s / real'(CLK_FREQ_HZ);
    localparam realtime BIT_TIME = CPB * CLK_PERIOD;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic rx = 1'b1;
    wire tx;
    integer transactions = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    pbit_top dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .uart_rx_i (rx),
        .uart_tx_o (tx)
    );

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
        if (tx !== 1'b0) $fatal(1, "UART response start bit");
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            #(BIT_TIME);
            value[bit_idx] = tx;
        end
        #(BIT_TIME);
        if (tx !== 1'b1) $fatal(1, "UART response stop bit");
    endtask

    task automatic uart_access(
        input logic [7:0] opcode,
        input logic [15:0] address,
        input logic [31:0] value,
        input logic [7:0] expected_status,
        output logic [31:0] result
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
            $fatal(1, "UART response request=%h response=%h", request, response);
        result = response[31:0];
        transactions++;
        #(2*BIT_TIME);
    endtask

    task automatic uart_write(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        uart_access(8'h01, address, value, 8'h00, ignored);
    endtask

    task automatic uart_check(input logic [15:0] address, input logic [31:0] expected);
        logic [31:0] actual;
        uart_access(8'h02, address, 32'd0, 8'h00, actual);
        if (actual !== expected)
            $fatal(1, "UART read address=%h actual=%h expected=%h", address, actual, expected);
    endtask

    initial begin : TEST
        logic [31:0] status;
        logic [31:0] snapshot_word;

        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);

        // Actual counts are encoded as value-1: two sweeps, majority of five.
        uart_write(A_GLOBAL_CFG, 32'h0400_0001);
        uart_check(A_GLOBAL_CFG, 32'h0400_0001);
        uart_write(A_I0_LEVEL0, 32'h0f0b_0703);
        uart_check(A_I0_LEVEL0, 32'h0f0b_0703);
        uart_write(A_SWEEP_INTERVAL0, 32'd0);

        // Configure and read back one clamped spin through the production UART.
        uart_write(A_UNIT_TARGET, 32'd0);
        uart_write(A_NODE_TARGET, 32'd0);
        uart_write(A_NODE_CFG, 32'h0000_0703);
        uart_write(A_NODE_CMD, (1 << APPLY_CFG_LSB) | (1 << READBACK_CFG_LSB));
        uart_check(A_NODE_RDATA_CFG, 32'h0000_0007);

        uart_write(A_SEED_TARGET, 32'd0);
        uart_write(A_SEED, 32'h1234_5678);
        uart_write(A_SEED_CMD, (1 << APPLY_SEED_LSB) | (1 << READBACK_SEED_LSB));
        uart_check(A_SEED_RDATA, 32'h1234_5678);

        uart_write(A_EDGE_TARGET, 32'd0);
        uart_write(A_EDGE_CFG, 32'h0000_01ff);
        uart_write(A_EDGE_CMD, (1 << APPLY_EDGE_LSB) | (1 << READBACK_EDGE_LSB));
        uart_check(A_EDGE_RDATA, 32'h0000_01ff);

        // The configured initial/clamped node is physical spin zero.
        uart_write(A_SNAPSHOT_ADDR, 32'd0);
        uart_write(A_GLOBAL_CTRL, 1 << SNAPSHOT_LATCH_LSB);
        uart_access(8'h02, A_GLOBAL_STATUS, 32'd0, 8'h00, status);
        if (!status[SNAPSHOT_VALID_LSB])
            $fatal(1, "Initial UART snapshot did not become valid: %h", status);
        uart_check(A_SPIN_RDATA0, 32'h0000_0001);

        uart_write(A_GLOBAL_CTRL, 1 << CFG_DONE_SET_LSB);
        uart_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        uart_access(8'h02, A_GLOBAL_STATUS, 32'd0, 8'h00, status);
        if (!status[CFG_DONE_LSB] || !status[RUN_DONE_LSB] ||
            status[RUN_BUSY_LSB] || status[ERROR_LSB])
            $fatal(1, "Unexpected post-run UART status: %h", status);

        uart_write(A_SNAPSHOT_ADDR, 32'd0);
        uart_write(A_GLOBAL_CTRL, 1 << SNAPSHOT_LATCH_LSB);
        uart_access(8'h02, A_GLOBAL_STATUS, 32'd0, 8'h00, status);
        if (!status[SNAPSHOT_VALID_LSB])
            $fatal(1, "Final UART snapshot did not become valid: %h", status);
        uart_access(8'h02, A_SPIN_RDATA0, 32'd0, 8'h00, snapshot_word);
        if (snapshot_word[0] !== 1'b1)
            $fatal(1, "Clamped spin changed after RUN: %h", snapshot_word);
        uart_check(A_ERROR_STATUS, 32'd0);

        uart_write(A_GLOBAL_CTRL, 1 << RUN_DONE_CLEAR_LSB);
        uart_check(A_GLOBAL_STATUS, 1 << CFG_DONE_LSB);
        $display("[TB_UART_END_TO_END] PASS transactions=%0d sweeps=2 majority=5", transactions);
        $finish;
    end

    initial begin
        #20ms;
        $fatal(1, "TB_UART_END_TO_END timeout");
    end
endmodule
