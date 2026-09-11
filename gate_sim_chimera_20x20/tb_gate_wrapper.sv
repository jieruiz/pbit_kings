`timescale 1ns/1ps

// Pin-only gate-level smoke test. It deliberately avoids all DUT hierarchy
// references so synthesis ungrouping and net renaming do not affect the test.
module tb_gate_wrapper;
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

    logic [15:0] pll_cfg;
    integer core_transactions = 0;
    integer test_stage = 0;
    integer ref_edge_count = 0;
    integer cfg_tx_edge_count = 0;
    integer core_tx_edge_count = 0;
`ifdef GATE_INTERNAL_DIAG
    integer internal_ref_edge_count = 0;
    integer internal_cfg_rx_edge_count = 0;
    integer internal_cfg_tx_edge_count = 0;
`endif

    assign avdd = 1'b1;
    assign dvdd = 1'b1;
    assign dvdd_drv = 1'b1;
    assign avss = 1'b0;
    assign dvss = 1'b0;
    assign dvss_drv = 1'b0;

    always #(REF_PERIOD_NS / 2.0) ref_clk = ~ref_clk;
    always @(posedge ref_clk) ref_edge_count = ref_edge_count + 1;
    always @(cfg_tx) cfg_tx_edge_count = cfg_tx_edge_count + 1;
    always @(core_tx) core_tx_edge_count = core_tx_edge_count + 1;
`ifdef GATE_INTERNAL_DIAG
    always @(posedge dut.ref_clk)
        internal_ref_edge_count = internal_ref_edge_count + 1;
    always @(dut.cfg_rx)
        internal_cfg_rx_edge_count = internal_cfg_rx_edge_count + 1;
    always @(dut.cfg_tx)
        internal_cfg_tx_edge_count = internal_cfg_tx_edge_count + 1;
`endif

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
        pll_cfg = 16'h021c;
        void'($value$plusargs("PLL_CFG=%h", pll_cfg));
    end

    // Generated per job by run_gate_sim_sbatch.sh. VCS 2018 requires the SDF
    // filename to be a compile-time character literal, not a runtime string.
    `include "gate_sdf_setup.svh"

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
            $fatal(1, "Nonzero write response address=%h data=%h", address, reply);
    endtask

    task automatic core_read_check(
        input logic [15:0] address,
        input logic [31:0] expected
    );
        logic [31:0] actual;
        core_access(8'h02, address, 32'd0, actual);
        if (actual !== expected)
            $fatal(1, "Read address=%h actual=%h expected=%h",
                   address, actual, expected);
    endtask

    initial begin : TEST
        // Gate-level UDP flops are not guaranteed to reset when reset merely
        // starts low at time zero. Generate a real asynchronous assertion edge.
        #(2 * REF_PERIOD_NS);
        pad_rst_n = 1'b0;
        #(10 * REF_PERIOD_NS);
        @(negedge ref_clk);
        pad_rst_n = 1'b1;
        #(25 * REF_PERIOD_NS);

        // Program and apply the operating point used to synthesize this netlist.
        test_stage = 1;
        $display("[GATE_STAGE] PLL shadow write time=%0t", $time);
`ifdef GATE_INTERNAL_DIAG
        $display("[GATE_INTERNAL] tie_hi=%b tie_lo=%b ref_clk=%b core_arst_n=%b ref_rst_n=%b cfg_rx=%b cfg_tx=%b",
                 dut.tie_hi, dut.tie_lo, dut.ref_clk, dut.core_arst_n,
                 dut.ref_rst_n, dut.cfg_rx, dut.cfg_tx);
`endif
        pll_access({8'h01, 8'h00, pll_cfg}, 32'h0000_0000);
        test_stage = 2;
        $display("[GATE_STAGE] PLL apply time=%0t", $time);
        pll_access(32'h0102_0001, 32'h0002_0000);
        test_stage = 3;
        $display("[GATE_STAGE] PLL startup wait time=%0t", $time);
        #20us;
        test_stage = 4;
        $display("[GATE_STAGE] PLL status/readback time=%0t", $time);
        pll_access(32'h0204_0000, 32'h0004_0072);
        pll_access(32'h0206_0000, {8'h00, 8'h06, pll_cfg});

        // External-pin smoke test of the synthesized core UART/register path.
        test_stage = 5;
        $display("[GATE_STAGE] core UART write/read time=%0t", $time);
        core_write(16'h0004, 32'h0400_0001);
        core_read_check(16'h0004, 32'h0400_0001);
        core_read_check(16'h000c, 32'h0000_0000);

        test_stage = 6;
        $display("[TB_GATE_WRAPPER] PASS pll_cfg=0x%04h core_transactions=%0d",
                 pll_cfg, core_transactions);
        $finish;
    end

    initial begin
        #10ms;
        $display("[GATE_TIMEOUT] stage=%0d pad_rst_n=%b cfg_rx=%b cfg_tx=%b core_rx=%b core_tx=%b",
                 test_stage, pad_rst_n, cfg_rx, cfg_tx, core_rx, core_tx);
        $display("[GATE_TIMEOUT] ref_edges=%0d cfg_tx_edges=%0d core_tx_edges=%0d core_transactions=%0d",
                 ref_edge_count, cfg_tx_edge_count, core_tx_edge_count,
                 core_transactions);
`ifdef GATE_INTERNAL_DIAG
        $display("[GATE_INTERNAL_TIMEOUT] tie_hi=%b tie_lo=%b ref_clk=%b core_arst_n=%b ref_rst_n=%b cfg_rx=%b cfg_tx=%b",
                 dut.tie_hi, dut.tie_lo, dut.ref_clk, dut.core_arst_n,
                 dut.ref_rst_n, dut.cfg_rx, dut.cfg_tx);
        $display("[GATE_INTERNAL_TIMEOUT] pll_en=%b core_release=%b core_clk=%b core_rst_n=%b internal_ref_edges=%0d internal_cfg_rx_edges=%0d internal_cfg_tx_edges=%0d",
                 dut.pll_en, dut.core_release, dut.core_clk, dut.core_rst_n,
                 internal_ref_edge_count, internal_cfg_rx_edge_count,
                 internal_cfg_tx_edge_count);
`endif
        $fatal(1, "TB_GATE_WRAPPER timeout");
    end
endmodule
