`timescale 1ns/1ps

// Pin-only zero-delay gate test for a concrete two-node MaxCut problem.
// No DUT hierarchy is used for functional checks, so the test remains valid
// after Design Compiler ungrouping and net renaming.
module tb_gate_chimera_problem;
    localparam realtime REF_PERIOD_NS = 40.0;
    localparam realtime CFG_BIT_NS = 1000.0;
    localparam realtime CORE_BIT_NS = 1000.0;

    // Core register map used through the external production UART.
    localparam logic [15:0] A_GLOBAL_CTRL    = 16'h0000;
    localparam logic [15:0] A_GLOBAL_CFG     = 16'h0004;
    localparam logic [15:0] A_GLOBAL_STATUS  = 16'h0008;
    localparam logic [15:0] A_ERROR_STATUS   = 16'h000c;
    localparam logic [15:0] A_SNAPSHOT_ADDR  = 16'h0010;
    localparam logic [15:0] A_I0_LEVEL0      = 16'h0014;
    localparam logic [15:0] A_SWEEP_INTERVAL0 = 16'h0034;
    localparam logic [15:0] A_UNIT_TARGET    = 16'h0074;
    localparam logic [15:0] A_NODE_TARGET    = 16'h0078;
    localparam logic [15:0] A_NODE_CFG       = 16'h007c;
    localparam logic [15:0] A_NODE_CMD       = 16'h0080;
    localparam logic [15:0] A_NODE_RDATA_CFG = 16'h0084;
    localparam logic [15:0] A_SEED_TARGET    = 16'h0088;
    localparam logic [15:0] A_SEED           = 16'h008c;
    localparam logic [15:0] A_SEED_CMD       = 16'h0090;
    localparam logic [15:0] A_SEED_RDATA     = 16'h0094;
    localparam logic [15:0] A_EDGE_TARGET    = 16'h0098;
    localparam logic [15:0] A_EDGE_CFG       = 16'h009c;
    localparam logic [15:0] A_EDGE_CMD       = 16'h00a0;
    localparam logic [15:0] A_EDGE_RDATA     = 16'h00a4;
    localparam logic [15:0] A_SPIN_RDATA0    = 16'h00a8;

    localparam int CFG_DONE_SET_BIT  = 0;
    localparam int RUN_START_BIT     = 2;
    localparam int SNAPSHOT_LATCH_BIT = 3;
    localparam int RUN_DONE_CLEAR_BIT = 4;
    localparam int CFG_DONE_BIT      = 0;
    localparam int RUN_BUSY_BIT      = 1;
    localparam int RUN_DONE_BIT      = 2;
    localparam int SNAPSHOT_VALID_BIT = 5;
    localparam int ERROR_BIT         = 6;

    // One actual sweep and five majority samples are encoded as value-1.
    localparam logic [31:0] GLOBAL_CFG_ONE_SWEEP_MAJ5 = 32'h0400_0000;
    localparam logic [31:0] I0_MAX_FIRST_FOUR_ROUNDS  = 32'h1f1f_1f1f;
    localparam logic [31:0] NODE0_CLAMP_HIGH_CFG      = 32'h0000_0703;
    localparam logic [31:0] NODE4_INIT_HIGH_CFG       = 32'h0000_0101;
    // valid=1, sign=0 (J=-1), probability=127: a MaxCut edge.
    localparam logic [31:0] ANTIFERRO_EDGE_MAX_CFG    = 32'h0000_01fd;

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
        pll_cfg = 16'h021c;
        void'($value$plusargs("PLL_CFG=%h", pll_cfg));
    end

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

    task automatic capture_word0(output logic [31:0] snapshot_word);
        logic [31:0] status;
        core_write(A_SNAPSHOT_ADDR, 32'd0);
        core_write(A_GLOBAL_CTRL, 32'(1 << SNAPSHOT_LATCH_BIT));
        core_read(A_GLOBAL_STATUS, status);
        if (!status[SNAPSHOT_VALID_BIT] || status[ERROR_BIT])
            $fatal(1, "Snapshot status invalid: %h", status);
        core_read(A_SPIN_RDATA0, snapshot_word);
    endtask

    initial begin : TEST
        logic [31:0] status;
        logic [31:0] before_spins;
        logic [31:0] after_spins;

        // UDP flops need a real asynchronous assertion edge at gate level.
        #(2 * REF_PERIOD_NS);
        pad_rst_n = 1'b0;
        #(10 * REF_PERIOD_NS);
        @(negedge ref_clk);
        pad_rst_n = 1'b1;
        #(25 * REF_PERIOD_NS);

        test_stage = 1;
        $display("[GATE_PROBLEM_STAGE] PLL shadow write time=%0t", $time);
        pll_access({8'h01, 8'h00, pll_cfg}, 32'h0000_0000);
        pll_access(32'h0102_0001, 32'h0002_0000);
        #20us;
        pll_access(32'h0204_0000, 32'h0004_0072);
        pll_access(32'h0206_0000, {8'h00, 8'h06, pll_cfg});

        test_stage = 2;
        $display("[GATE_PROBLEM_STAGE] global schedule configuration time=%0t", $time);
        core_write(A_GLOBAL_CFG, GLOBAL_CFG_ONE_SWEEP_MAJ5);
        core_read_check(A_GLOBAL_CFG, GLOBAL_CFG_ONE_SWEEP_MAJ5);
        core_write(A_I0_LEVEL0, I0_MAX_FIRST_FOUR_ROUNDS);
        core_read_check(A_I0_LEVEL0, I0_MAX_FIRST_FOUR_ROUNDS);
        core_write(A_SWEEP_INTERVAL0, 32'd0);
        core_read_check(A_SWEEP_INTERVAL0, 32'd0);

        test_stage = 3;
        $display("[GATE_PROBLEM_STAGE] two-node MaxCut configuration time=%0t", $time);
        core_write(A_UNIT_TARGET, 32'd0);
        core_read_check(A_UNIT_TARGET, 32'd0);

        // Node 0 is the fixed +1 reference on the left shore.
        core_write(A_NODE_TARGET, 32'h0000_0000);
        core_write(A_NODE_CFG, NODE0_CLAMP_HIGH_CFG);
        core_write(A_NODE_CMD, 32'h0000_0003);
        core_read_check(A_NODE_RDATA_CFG, 32'h0000_0007);

        // Node 4 is the free right-shore node, deliberately initialized high.
        core_write(A_NODE_TARGET, 32'h0000_0100);
        core_write(A_NODE_CFG, NODE4_INIT_HIGH_CFG);
        core_write(A_NODE_CMD, 32'h0000_0003);
        core_read_check(A_NODE_RDATA_CFG, 32'h0000_0001);

        core_write(A_SEED_TARGET, 32'd0);
        core_write(A_SEED, 32'h1357_9bdf);
        core_write(A_SEED_CMD, 32'h0000_0003);
        core_read_check(A_SEED_RDATA, 32'h1357_9bdf);

        // Edge type 0, number 0 connects node 0 to node 4 in unit (0,0).
        core_write(A_EDGE_TARGET, 32'h0000_0000);
        core_write(A_EDGE_CFG, ANTIFERRO_EDGE_MAX_CFG);
        core_write(A_EDGE_CMD, 32'h0000_0005);
        core_read_check(A_EDGE_RDATA, ANTIFERRO_EDGE_MAX_CFG);
        core_read_check(A_ERROR_STATUS, 32'd0);

        test_stage = 4;
        capture_word0(before_spins);
        if (before_spins[0] !== 1'b1 || before_spins[4] !== 1'b1)
            $fatal(1, "Wrong initial problem state word0=%h", before_spins);
        $display("[GATE_PROBLEM] before run spin0=%0b spin4=%0b cut=0",
                 before_spins[0], before_spins[4]);

        test_stage = 5;
        core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));
        core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
        core_read(A_GLOBAL_STATUS, status);
        if (!status[CFG_DONE_BIT] || !status[RUN_DONE_BIT] ||
            status[RUN_BUSY_BIT] || status[ERROR_BIT])
            $fatal(1, "Unexpected post-run status=%h", status);

        test_stage = 6;
        capture_word0(after_spins);
        if (after_spins[0] !== 1'b1)
            $fatal(1, "Clamped node 0 changed: word0=%h", after_spins);
        if (after_spins[4] !== 1'b0)
            $fatal(1, "MaxCut node 4 did not flip: word0=%h", after_spins);
        core_read_check(A_ERROR_STATUS, 32'd0);
        $display("[GATE_PROBLEM] after run spin0=%0b spin4=%0b cut=1",
                 after_spins[0], after_spins[4]);

        core_write(A_GLOBAL_CTRL, 32'(1 << RUN_DONE_CLEAR_BIT));
        core_read(A_GLOBAL_STATUS, status);
        if (status[RUN_DONE_BIT] || !status[CFG_DONE_BIT] || status[ERROR_BIT])
            $fatal(1, "RUN_DONE clear failed status=%h", status);

        test_stage = 7;
        $display("[TB_GATE_CHIMERA_PROBLEM] PASS problem=two_node_maxcut sweeps=1 majority=5 transactions=%0d",
                 core_transactions);
        $finish;
    end

    initial begin
        #20ms;
        $display("[GATE_PROBLEM_TIMEOUT] stage=%0d pad_rst_n=%b cfg_tx=%b core_tx=%b transactions=%0d",
                 test_stage, pad_rst_n, cfg_tx, core_tx, core_transactions);
        $fatal(1, "TB_GATE_CHIMERA_PROBLEM timeout");
    end
endmodule
