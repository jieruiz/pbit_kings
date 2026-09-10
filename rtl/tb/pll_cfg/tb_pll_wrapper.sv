`timescale 1ns/1ps
import pbit_pkg::*;

// Full digital integration test:
// pad stubs -> 25 MHz PLL-config UART -> PLL model -> reset release ->
// production UART -> Chimera register/configuration/run/snapshot path.
module tb_pll_wrapper;
    localparam realtime REF_PERIOD_NS = 1.0e9 / REF_CLK_FREQ_HZ;
    localparam realtime CFG_BIT_NS = 1.0e9 / PLL_CFG_BAUD_RATE;
    localparam realtime CORE_BIT_NS = 1.0e9 / BAUD_RATE;
    localparam realtime EXPECTED_CORE_PERIOD_NS = 1.0e9 / CLK_FREQ_HZ;

    logic ref_clk = 1'b0;
    logic pad_rst_n = 1'b0;
    wire cfg_rx;
    wire cfg_tx;
    logic core_rx = 1'b1;
    wire core_tx;
    tri avdd;
    tri avss;
    tri dvdd;
    tri dvss;
    tri dvdd_drv;
    tri dvss_drv;
    integer core_transactions = 0;

    assign avdd = 1'b1;
    assign dvdd = 1'b1;
    assign dvdd_drv = 1'b1;
    assign avss = 1'b0;
    assign dvss = 1'b0;
    assign dvss_drv = 1'b0;

    always #(REF_PERIOD_NS / 2.0) ref_clk = ~ref_clk;

    uart_host #(.BIT_NS(CFG_BIT_NS)) host (
        .rx (cfg_rx),
        .tx (cfg_tx)
    );

    pbit_io_wrapper dut (
        .pad_clk_i        (ref_clk),
        .pad_rst_n_i      (pad_rst_n),
        .pad_uart_rx_i    (core_rx),
        .pad_uart_tx_o    (core_tx),
        .pad_pll_cfg_rx_i (cfg_rx),
        .pad_pll_cfg_tx_o (cfg_tx),
        .pll_avdd          (avdd),
        .pll_avss          (avss),
        .pll_dvdd          (dvdd),
        .pll_dvss          (dvss),
        .pll_dvdd_drv      (dvdd_drv),
        .pll_dvss_drv      (dvss_drv)
    );

    task automatic pll_access(
        input logic [31:0] request,
        input logic [31:0] expected
    );
        logic [31:0] reply;
        host.transfer4(request, reply);
        if (reply !== expected)
            $fatal(1, "PLL cfg request=%h reply=%h expected=%h",
                   request, reply, expected);
    endtask

    task automatic check_core_period(input realtime expected_ns);
        realtime start_time;
        realtime measured_ns;
        @(posedge dut.core_clk);
        start_time = $realtime;
        repeat (100) @(posedge dut.core_clk);
        measured_ns = ($realtime - start_time) / 100.0;
        if (measured_ns < expected_ns - 0.005 ||
            measured_ns > expected_ns + 0.005)
            $fatal(1, "PLL period=%0.4f ns expected=%0.4f ns",
                   measured_ns, expected_ns);
        $display("[PLL_WRAPPER] core_period_ns=%0.4f", measured_ns);
    endtask

    task automatic reconfigure_pll(
        input logic [15:0] config,
        input logic [15:0] expected_status,
        input realtime expected_period_ns
    );
        pll_access({8'h01, 8'h00, config}, 32'h0000_0000);
        fork
            begin
                pll_access(32'h0102_0001, 32'h0002_0000);
            end
            begin
                @(negedge dut.core_rst_n);
                @(posedge dut.core_rst_n);
            end
        join
        pll_access(32'h0204_0000, {8'h00, 8'h04, expected_status});
        pll_access(32'h0206_0000, {8'h00, 8'h06, config});
        check_core_period(expected_period_ns);
    endtask

    task automatic send_core_byte(input logic [7:0] value);
        core_rx = 1'b0;
        #(CORE_BIT_NS);
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            core_rx = value[bit_idx];
            #(CORE_BIT_NS);
        end
        core_rx = 1'b1;
        #(CORE_BIT_NS);
    endtask

    task automatic receive_core_byte(output logic [7:0] value);
        @(negedge core_tx);
        #(CORE_BIT_NS / 2.0);
        if (core_tx !== 1'b0)
            $fatal(1, "Production UART false start");
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            #(CORE_BIT_NS);
            value[bit_idx] = core_tx;
        end
        #(CORE_BIT_NS);
        if (core_tx !== 1'b1)
            $fatal(1, "Production UART invalid stop bit");
        #(CORE_BIT_NS / 2.0);
    endtask

    task automatic core_access(
        input  logic [7:0]  opcode,
        input  logic [15:0] address,
        input  logic [31:0] data,
        output logic [31:0] value
    );
        logic [55:0] request;
        logic [55:0] reply;
        logic [7:0] received;
        request = {opcode, address, data};
        reply = '0;
        fork
            begin
                for (int byte_idx = 6; byte_idx >= 0; byte_idx--)
                    send_core_byte(request[byte_idx*8 +: 8]);
            end
            begin
                for (int byte_idx = 6; byte_idx >= 0; byte_idx--) begin
                    receive_core_byte(received);
                    reply[byte_idx*8 +: 8] = received;
                end
            end
        join
        if (reply[55:48] !== 8'h00 || reply[47:32] !== address)
            $fatal(1, "Production UART request=%h reply=%h", request, reply);
        value = reply[31:0];
        core_transactions = core_transactions + 1;
        #(CORE_BIT_NS * 2.0);
    endtask

    task automatic core_write(
        input logic [15:0] address,
        input logic [31:0] value
    );
        logic [31:0] ignored;
        core_access(8'h01, address, value, ignored);
        if (ignored !== 32'd0)
            $fatal(1, "Nonzero production-UART write response at %h", address);
    endtask

    task automatic core_read_check(
        input logic [15:0] address,
        input logic [31:0] expected
    );
        logic [31:0] actual;
        core_access(8'h02, address, 32'd0, actual);
        if (actual !== expected)
            $fatal(1, "Read %h actual=%h expected=%h", address, actual, expected);
    endtask

    task automatic chimera_core_smoke;
        logic [31:0] unit_target;
        logic [31:0] node_target;
        logic [31:0] edge_target;
        logic [31:0] status;
        logic [31:0] snapshot_word;
        int flat_idx;
        int page_idx;
        int word_idx;
        int bit_idx;

        unit_target = (32'(ROWS-1) << UNIT_TARGET_ROW_LSB) |
                      (32'(COLS-1) << UNIT_TARGET_COL_LSB);
        // Last local p-bit: shore 1, track 3.
        node_target = (32'd3 << NODE_TARGET_ROW_LSB) |
                      (32'd1 << NODE_TARGET_COL_LSB);

        core_write(A_GLOBAL_CFG, 32'h0400_0001);
        core_read_check(A_GLOBAL_CFG, 32'h0400_0001);
        core_write(A_I0_LEVEL0, 32'h0f0b_0703);
        core_read_check(A_I0_LEVEL0, 32'h0f0b_0703);
        core_write(A_SWEEP_INTERVAL0, 32'd0);

        core_write(A_UNIT_TARGET, unit_target);
        core_read_check(A_UNIT_TARGET, unit_target);
        core_write(A_NODE_TARGET, node_target);
        core_read_check(A_NODE_TARGET, node_target);
        // Initialize and clamp the selected p-bit high.
        core_write(A_NODE_CFG, 32'h0000_0703);
        core_write(A_NODE_CMD,
                   (1 << APPLY_CFG_LSB) | (1 << READBACK_CFG_LSB));
        core_read_check(A_NODE_RDATA_CFG, 32'h0000_0007);

        core_write(A_SEED_TARGET, 32'd3);
        core_write(A_SEED, 32'h1357_9bdf);
        core_write(A_SEED_CMD,
                   (1 << APPLY_SEED_LSB) | (1 << READBACK_SEED_LSB));
        core_read_check(A_SEED_RDATA, 32'h1357_9bdf);

        // Intra-cell edge type zero is legal at every unit coordinate.
        edge_target = (32'd0 << EDGE_TYPE_LSB) |
                      (32'd0 << EDGE_TARGET_NUMBER_LSB);
        core_write(A_EDGE_TARGET, edge_target);
        core_write(A_EDGE_CFG, 32'h0000_01ff);
        core_write(A_EDGE_CMD,
                   (1 << APPLY_EDGE_LSB) | (1 << READBACK_EDGE_LSB));
        core_read_check(A_EDGE_RDATA, 32'h0000_01ff);

        flat_idx = ((ROWS-1) * COLS + (COLS-1)) * NODE_IN_UNIT + 7;
        page_idx = flat_idx / SNAPSHOT_WIDTH;
        word_idx = (flat_idx % SNAPSHOT_WIDTH) / 32;
        bit_idx = flat_idx % 32;
        core_write(A_SNAPSHOT_ADDR, 32'(page_idx));
        core_write(A_GLOBAL_CTRL, 1 << SNAPSHOT_LATCH_LSB);
        core_access(8'h02, A_GLOBAL_STATUS, 32'd0, status);
        if (!status[SNAPSHOT_VALID_LSB])
            $fatal(1, "Initial snapshot did not become valid: %h", status);
        core_access(8'h02, A_SPIN_RDATA0 + 16'(4*word_idx),
                    32'd0, snapshot_word);
        if (snapshot_word[bit_idx] !== 1'b1)
            $fatal(1, "Clamped p-bit missing from initial snapshot: %h",
                   snapshot_word);

        core_write(A_GLOBAL_CTRL, 1 << CFG_DONE_SET_LSB);
        core_write(A_GLOBAL_CTRL, 1 << RUN_START_LSB);
        core_access(8'h02, A_GLOBAL_STATUS, 32'd0, status);
        if (!status[CFG_DONE_LSB] || !status[RUN_DONE_LSB] ||
            status[RUN_BUSY_LSB] || status[ERROR_LSB])
            $fatal(1, "Unexpected post-run status: %h", status);

        core_write(A_SNAPSHOT_ADDR, 32'(page_idx));
        core_write(A_GLOBAL_CTRL, 1 << SNAPSHOT_LATCH_LSB);
        core_access(8'h02, A_GLOBAL_STATUS, 32'd0, status);
        if (!status[SNAPSHOT_VALID_LSB])
            $fatal(1, "Final snapshot did not become valid: %h", status);
        core_access(8'h02, A_SPIN_RDATA0 + 16'(4*word_idx),
                    32'd0, snapshot_word);
        if (snapshot_word[bit_idx] !== 1'b1)
            $fatal(1, "Clamped p-bit changed after RUN: %h", snapshot_word);
        core_read_check(A_ERROR_STATUS, 32'd0);

        $display("[PLL_WRAPPER] Chimera UART/config/run/snapshot PASS pbits=%0d",
                 N_SPIN);
    endtask

    initial begin : TEST
        realtime enable_time;

        #(10 * REF_PERIOD_NS);
        @(negedge ref_clk);
        pad_rst_n = 1'b1;
        #(25 * REF_PERIOD_NS);

        if (dut.pll_en !== 1'b0 || dut.core_rst_n !== 1'b0)
            $fatal(1, "Core enabled before PLL APPLY");

        pll_access(32'h0200_0000, 32'h0000_0220);
        fork
            begin
                pll_access(32'h0102_0001, 32'h0002_0000);
            end
            begin
                @(posedge dut.pll_en);
                enable_time = $realtime;
                @(posedge dut.core_rst_n);
                if (($realtime - enable_time) < 15000.0)
                    $fatal(1, "Core released before the 15 us startup wait");
            end
        join
        pll_access(32'h0204_0000, 32'h0004_0072);
        pll_access(32'h0206_0000, 32'h0006_0220);
        check_core_period(EXPECTED_CORE_PERIOD_NS);

        // BP=1 routes the 25 MHz reference clock to CKOUT1. Reconfiguration
        // must reset the core, then report BP_ACTIVE and a 40 ns period.
        reconfigure_pll(16'h0a20, 16'h007a, REF_PERIOD_NS);
        $display("[PLL_WRAPPER] 25 MHz bypass PASS");

        // Restore the compiled 400 MHz operating point before using the
        // production UART, whose fixed divider assumes CLK_FREQ_HZ.
        reconfigure_pll(16'h0220, 16'h0072, EXPECTED_CORE_PERIOD_NS);
        $display("[PLL_WRAPPER] 400 MHz restore PASS");
        chimera_core_smoke();

        $display("[TB_PLL_WRAPPER] PASS ref_hz=%0d core_hz=%0d cfg_baud=%0d core_baud=%0d transactions=%0d",
                 REF_CLK_FREQ_HZ, CLK_FREQ_HZ, PLL_CFG_BAUD_RATE,
                 BAUD_RATE, core_transactions);
        $finish;
    end

    initial begin
        #20ms;
        $fatal(1, "TB_PLL_WRAPPER timeout");
    end
endmodule
