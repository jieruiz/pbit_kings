`timescale 1ns/1ps

// Shared pin-only environment for the synthesized pbit_io_wrapper. Functional
// checks intentionally avoid DUT hierarchy so DC ungrouping cannot break them.
module gate_pipeline_env;
    localparam realtime REF_PERIOD_NS = 40.0;
    localparam realtime CFG_BIT_NS = 1000.0;
    localparam realtime CORE_BIT_NS = 1000.0;

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
            $fatal(1, "Nonzero write reply address=%h reply=%h",
                   address, reply);
    endtask

    task automatic core_read(
        input  logic [15:0] address,
        output logic [31:0] value
    );
        core_access(8'h02, address, 32'd0, value);
    endtask

    task automatic core_read_check(
        input logic [15:0] address,
        input logic [31:0] expected
    );
        logic [31:0] actual;
        core_read(address, actual);
        if (actual !== expected)
            $fatal(1, "Read address=%h actual=%h expected=%h",
                   address, actual, expected);
    endtask

    task automatic initialize(input logic [15:0] pll_cfg);
        // Gate-level UDP flops need a real asynchronous assertion edge.
        #(2 * REF_PERIOD_NS);
        pad_rst_n = 1'b0;
        #(10 * REF_PERIOD_NS);
        @(negedge ref_clk);
        pad_rst_n = 1'b1;
        #(25 * REF_PERIOD_NS);

        $display("[GATE_INIT] PLL shadow=0x%04h time=%0t", pll_cfg, $time);
        pll_access({8'h01, 8'h00, pll_cfg}, 32'h0000_0000);
        pll_access(32'h0102_0001, 32'h0002_0000);
        #20us;
        pll_access(32'h0204_0000, 32'h0004_0072);
        pll_access(32'h0206_0000, {8'h00, 8'h06, pll_cfg});
        $display("[GATE_INIT] PLL applied, core UART ready time=%0t", $time);
    endtask
endmodule
