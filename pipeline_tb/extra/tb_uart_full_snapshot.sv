`timescale 1ns/1ps
import pbit_pkg::*;

// Full-chip readout regression. Configuration uses the test-only bus mux to
// keep setup short; every snapshot command and all 3200 output bits traverse
// the production 1-Mbps UART request/response path.
module tb_uart_full_snapshot;
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

    logic [N_SPIN-1:0] expected_spins = '0;
    logic [N_SPIN-1:0] captured_spins = '0;
    integer uart_transactions = 0;

    always #(CLK_PERIOD/2) clk = ~clk;
    chimera_problem_harness dut (.*);

    task automatic bus_access(
        input bit write_access,
        input logic [15:0] address,
        input logic [31:0] value,
        output logic [31:0] result
    );
        @(negedge clk);
        addr = address;
        wdata = value;
        wr_en = write_access;
        rd_en = !write_access;
        @(posedge clk);
        #(CLK_PERIOD/4);
        if (access_error)
            $fatal(1, "Setup bus error address=%h value=%h", address, value);
        result = rdata;
        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
    endtask

    task automatic bus_write(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        bus_access(1'b1, address, value, ignored);
    endtask

    task automatic wait_cfg_idle;
        integer waited;
        begin
            waited = 0;
            while (cfg_busy) begin
                @(negedge clk);
                waited++;
                if (waited > 100) $fatal(1, "CFG_BUSY timeout during setup");
            end
        end
    endtask

    task automatic configure_clamped_node(
        input integer unit_row,
        input integer unit_col,
        input integer node_number,
        input logic spin_value
    );
        logic [31:0] node_cfg;
        begin
            node_cfg = '0;
            node_cfg[INIT_VALID_LSB] = 1'b1;
            node_cfg[CLAMP_VALID_LSB] = 1'b1;
            node_cfg[NODE_CFG_INIT_SPIN_LSB] = spin_value;
            node_cfg[NODE_CFG_CLAMP_EN_LSB] = 1'b1;
            node_cfg[NODE_CFG_CLAMP_SPIN_LSB] = spin_value;
            bus_write(A_UNIT_TARGET,
                      unit_row | (unit_col << UNIT_TARGET_COL_LSB));
            bus_write(A_NODE_TARGET,
                      (node_number & 3) |
                      ((node_number >> 2) << NODE_TARGET_COL_LSB));
            bus_write(A_NODE_CFG, node_cfg);
            bus_write(A_NODE_CMD, 1 << APPLY_CFG_LSB);
            wait_cfg_idle();
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
        if (response[55:48] !== 8'h00 || response[47:32] !== address)
            $fatal(1, "UART response request=%h response=%h transaction=%0d",
                   request, response, uart_transactions+1);
        result = response[31:0];
        uart_transactions++;
        #(2*BIT_TIME);
    endtask

    task automatic uart_write(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        uart_access(8'h01, address, value, ignored);
    endtask

    task automatic uart_read(input logic [15:0] address, output logic [31:0] value);
        uart_access(8'h02, address, 32'd0, value);
    endtask

    initial begin : TEST
        logic [31:0] pattern_word;
        logic [31:0] actual_word;
        logic [31:0] status;
        logic [31:0] errors;
        integer flat;
        integer page;
        integer word_idx;
        integer unit_row;
        integer unit_col;
        integer node_number;
        integer waited;

        if (ROWS != 20 || COLS != 20 || N_SPIN != 3200 ||
            SNAPSHOT_WIDTH != 320 || SPIN_RDATA_REG_NUM != 10 ||
            SPIN_ADDR_MAX != 10)
            $fatal(1, "Expected the production 20x20/3200-bit snapshot geometry");

        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);

        // Give every 32-bit output word a different deterministic pattern.
        // This exposes page swaps, word swaps, bit reversal and stale pages.
        for (word_idx = 0; word_idx < N_SPIN/32; word_idx++) begin
            pattern_word = 32'ha5f0_3c69 ^ (32'h9e37_79b9 * word_idx);
            expected_spins[word_idx*32 +: 32] = pattern_word;
        end

        // Fast setup through the harness bus. The readout below does not use
        // this bypass and therefore exercises the exact external UART path.
        for (flat = 0; flat < N_SPIN; flat++) begin
            unit_row = (flat / NODE_IN_UNIT) / COLS;
            unit_col = (flat / NODE_IN_UNIT) % COLS;
            node_number = flat % NODE_IN_UNIT;
            configure_clamped_node(unit_row, unit_col, node_number,
                                   expected_spins[flat]);
        end

        // One complete run proves that the state is the post-compute state,
        // not merely configuration readback. All nodes are deliberately clamped.
        bus_write(A_GLOBAL_CFG, 32'd0); // one sweep, majority one
        bus_write(A_GLOBAL_CTRL, 1 << CFG_DONE_SET_LSB);
        bus_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        waited = 0;
        while (!run_done) begin
            @(negedge clk);
            waited++;
            if (waited > 100) $fatal(1, "RUN_DONE timeout");
        end
        if (run_busy || spins !== expected_spins)
            $fatal(1, "Post-run internal state mismatch busy=%b", run_busy);

        // From here onward act like the external host: serialized UART only.
        uart_mode = 1'b1;
        repeat (4) @(negedge clk);
        for (page = 0; page < SPIN_ADDR_MAX; page++) begin
            uart_write(A_SNAPSHOT_ADDR, page);
            uart_write(A_GLOBAL_CTRL, 1 << SNAPSHOT_LATCH_LSB);
            uart_read(A_GLOBAL_STATUS, status);
            if (!status[CFG_DONE_LSB] || !status[RUN_DONE_LSB] ||
                status[RUN_BUSY_LSB] || !status[SNAPSHOT_VALID_LSB] ||
                status[ERROR_LSB])
                $fatal(1, "Snapshot page=%0d status=%h", page, status);

            // Reading status clears VALID, but the captured 320-bit page must
            // remain unchanged during all ten slow UART word reads.
            for (word_idx = 0; word_idx < SPIN_RDATA_REG_NUM; word_idx++) begin
                uart_read(A_SPIN_RDATA0 + 4*word_idx, actual_word);
                captured_spins[(page*SPIN_RDATA_REG_NUM+word_idx)*32 +: 32] =
                    actual_word;
                if (actual_word !==
                    expected_spins[(page*SPIN_RDATA_REG_NUM+word_idx)*32 +: 32])
                    $fatal(1,
                        "UART snapshot mismatch page=%0d word=%0d actual=%h expected=%h",
                        page, word_idx, actual_word,
                        expected_spins[(page*SPIN_RDATA_REG_NUM+word_idx)*32 +: 32]);
            end
            $display("[UART_FULL_SNAPSHOT] page=%0d/%0d PASS",
                     page+1, SPIN_ADDR_MAX);
        end

        uart_read(A_ERROR_STATUS, errors);
        if (errors !== 32'd0) $fatal(1, "UART readout errors=%h", errors);
        if (uart_transactions !=
            SPIN_ADDR_MAX*(SPIN_RDATA_REG_NUM+3)+1)
            $fatal(1, "UART transaction count actual=%0d expected=%0d",
                   uart_transactions,
                   SPIN_ADDR_MAX*(SPIN_RDATA_REG_NUM+3)+1);
        if (captured_spins !== expected_spins || captured_spins !== spins)
            $fatal(1, "Complete 3200-bit UART reconstruction mismatch");

        $display("[TB_UART_FULL_SNAPSHOT] PASS bits=%0d pages=%0d words=%0d transactions=%0d",
                 N_SPIN, SPIN_ADDR_MAX, N_SPIN/32, uart_transactions);
        $finish;
    end

    initial begin
        #50ms;
        $fatal(1, "TB_UART_FULL_SNAPSHOT timeout");
    end
endmodule
