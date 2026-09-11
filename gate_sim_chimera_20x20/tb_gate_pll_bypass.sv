`timescale 1ns/1ps

// Zero-delay gate-netlist regression for PLL normal -> bypass -> normal.
// Configuration and core accesses use package pins. The internal core clock
// and reset are observed because neither signal is exported as a chip pin.
module tb_gate_pll_bypass;
    localparam realtime REF_PERIOD_NS = 40.0;
    localparam realtime CFG_BIT_NS = 1000.0;
    localparam realtime CORE_BIT_NS = 1000.0;
    localparam realtime CLOCK_TOLERANCE_NS = 0.010;

    localparam logic [15:0] A_GLOBAL_CFG = 16'h0004;
    localparam logic [15:0] A_ERROR_STATUS = 16'h000c;

    logic ref_clk = 1'b0;
    logic pad_rst_n = 1'b1;
    logic core_rx = 1'b1;
    wire cfg_rx;
    wire cfg_tx;
    wire core_tx;
    tri avdd;
    tri avss;
    tri dvdd;
    tri dvss;
    tri dvdd_drv;
    tri dvss_drv;

    logic [15:0] normal_cfg;
    logic [15:0] bypass_cfg;
    realtime normal_period_ns;
    integer core_transactions = 0;
    integer test_stage = 0;

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

    initial begin
        normal_cfg = 16'h021c;
        void'($value$plusargs("PLL_CFG=%h", normal_cfg));
        bypass_cfg = normal_cfg | 16'h0800;
        normal_period_ns = REF_PERIOD_NS * (1 << normal_cfg[10:9]) /
                           (normal_cfg[7:0] * (normal_cfg[8] ? 2.0 : 1.0));
    end

    task automatic pll_transfer(
        input  logic [31:0] request,
        output logic [31:0] reply
    );
        host.transfer4(request, reply);
    endtask

    task automatic pll_access_check(
        input logic [31:0] request,
        input logic [31:0] expected
    );
        logic [31:0] reply;
        pll_transfer(request, reply);
        if (reply !== expected)
            $fatal(1, "PLL request=%h reply=%h expected=%h",
                   request, reply, expected);
    endtask

    task automatic report_pll_status(input string reason);
        logic [31:0] status_reply;
        logic [31:0] active_reply;
        pll_transfer(32'h0204_0000, status_reply);
        pll_transfer(32'h0206_0000, active_reply);
        $display("[GATE_PLL_DIAG] %s status_reply=%h active_reply=%h EN=%b BP=%b core_clk=%b core_rst_n=%b",
                 reason, status_reply, active_reply, dut.pll_en, dut.pll_bp,
                 dut.core_clk, dut.core_rst_n);
    endtask

    task automatic wait_core_release(input logic require_assertion);
        logic saw_assertion;
        logic saw_release;
        saw_assertion = !require_assertion;
        saw_release = 1'b0;
        fork : RELEASE_WAIT
            begin
                if (require_assertion) begin
                    @(negedge dut.core_rst_n);
                    saw_assertion = 1'b1;
                end
                if (dut.core_rst_n !== 1'b1)
                    @(posedge dut.core_rst_n);
                saw_release = 1'b1;
            end
            begin
                // The APPLY UART transaction itself takes about 80 us at
                // 1 Mbps. Allow that plus the 15 us startup interval and the
                // reference-domain release timeout before declaring failure.
                #250us;
            end
        join_any
        disable RELEASE_WAIT;
        if (!saw_assertion || !saw_release) begin
            report_pll_status("core reset release timeout");
            $fatal(1, "PLL reconfiguration reset cycle failed assertion=%0b release=%0b",
                   saw_assertion, saw_release);
        end
    endtask

    task automatic check_core_period(
        input realtime expected_ns,
        input string mode_name
    );
        realtime start_time;
        realtime measured_ns;
        logic measurement_done;
        measurement_done = 1'b0;
        measured_ns = 0.0;
        fork : PERIOD_WAIT
            begin
                @(posedge dut.core_clk);
                start_time = $realtime;
                repeat (100) @(posedge dut.core_clk);
                measured_ns = ($realtime - start_time) / 100.0;
                measurement_done = 1'b1;
            end
            begin
                #20us;
            end
        join_any
        disable PERIOD_WAIT;
        if (!measurement_done) begin
            report_pll_status(mode_name);
            $fatal(1, "No usable core clock in %s mode", mode_name);
        end
        if (measured_ns < expected_ns - CLOCK_TOLERANCE_NS ||
            measured_ns > expected_ns + CLOCK_TOLERANCE_NS)
            $fatal(1, "%s period=%0.4f ns expected=%0.4f ns",
                   mode_name, measured_ns, expected_ns);
        $display("[GATE_PLL_CLOCK] mode=%s period_ns=%0.4f expected_ns=%0.4f",
                 mode_name, measured_ns, expected_ns);
    endtask

    task automatic apply_initial_config(input logic [15:0] config);
        pll_access_check({8'h01, 8'h00, config}, 32'h0000_0000);
        fork
            pll_access_check(32'h0102_0001, 32'h0002_0000);
            wait_core_release(1'b0);
        join
    endtask

    task automatic reconfigure_pll(input logic [15:0] config);
        pll_access_check({8'h01, 8'h00, config}, 32'h0000_0000);
        fork
            pll_access_check(32'h0102_0001, 32'h0002_0000);
            wait_core_release(1'b1);
        join
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
            $fatal(1, "Core UART false start");
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            #(CORE_BIT_NS);
            value[bit_idx] = core_tx;
        end
        #(CORE_BIT_NS);
        if (core_tx !== 1'b1)
            $fatal(1, "Core UART invalid stop bit");
        #(CORE_BIT_NS / 2.0);
    endtask

    task automatic core_access(
        input  logic [7:0] opcode,
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
            $fatal(1, "Core UART request=%h reply=%h", request, reply);
        value = reply[31:0];
        core_transactions = core_transactions + 1;
        #(CORE_BIT_NS * 2.0);
    endtask

    task automatic core_write(
        input logic [15:0] address,
        input logic [31:0] value
    );
        logic [31:0] reply;
        core_access(8'h01, address, value, reply);
        if (reply !== 32'd0)
            $fatal(1, "Core write returned nonzero data address=%h reply=%h",
                   address, reply);
    endtask

    task automatic core_read_check(
        input logic [15:0] address,
        input logic [31:0] expected
    );
        logic [31:0] actual;
        core_access(8'h02, address, 32'd0, actual);
        if (actual !== expected)
            $fatal(1, "Core read address=%h actual=%h expected=%h",
                   address, actual, expected);
    endtask

    initial begin : TEST
        // Generate a real asynchronous reset assertion for gate-level UDPs.
        #(2 * REF_PERIOD_NS);
        pad_rst_n = 1'b0;
        #(10 * REF_PERIOD_NS);
        @(negedge ref_clk);
        pad_rst_n = 1'b1;
        #(25 * REF_PERIOD_NS);

        test_stage = 1;
        $display("[GATE_PLL_STAGE] initial normal config=0x%04h", normal_cfg);
        apply_initial_config(normal_cfg);
        pll_access_check(32'h0204_0000, 32'h0004_0072);
        pll_access_check(32'h0206_0000, {8'h00, 8'h06, normal_cfg});
        check_core_period(normal_period_ns, "normal_initial");
        core_write(A_GLOBAL_CFG, 32'h0400_0001);
        core_read_check(A_GLOBAL_CFG, 32'h0400_0001);

        test_stage = 2;
        $display("[GATE_PLL_STAGE] switch to bypass config=0x%04h", bypass_cfg);
        reconfigure_pll(bypass_cfg);
        pll_access_check(32'h0204_0000, 32'h0004_007a);
        pll_access_check(32'h0206_0000, {8'h00, 8'h06, bypass_cfg});
        check_core_period(REF_PERIOD_NS, "bypass");
        $display("[GATE_PLL_BYPASS] PASS 25 MHz reference reached core clock");

        test_stage = 3;
        $display("[GATE_PLL_STAGE] restore normal config=0x%04h", normal_cfg);
        reconfigure_pll(normal_cfg);
        pll_access_check(32'h0204_0000, 32'h0004_0072);
        pll_access_check(32'h0206_0000, {8'h00, 8'h06, normal_cfg});
        check_core_period(normal_period_ns, "normal_restored");

        // PLL reconfiguration resets the core register block.
        core_read_check(A_GLOBAL_CFG, 32'h0000_0000);
        core_write(A_GLOBAL_CFG, 32'h0400_0001);
        core_read_check(A_GLOBAL_CFG, 32'h0400_0001);
        core_read_check(A_ERROR_STATUS, 32'h0000_0000);

        test_stage = 4;
        $display("[TB_GATE_PLL_BYPASS] PASS normal_period_ns=%0.4f bypass_period_ns=40.0000 core_transactions=%0d",
                 normal_period_ns, core_transactions);
        $finish;
    end

    initial begin
        #5ms;
        report_pll_status("global test timeout");
        $fatal(1, "TB_GATE_PLL_BYPASS timeout stage=%0d", test_stage);
    end
endmodule
