module tb_pll_wrapper;
    timeunit 1ns;
    timeprecision 1ps;
    import pbit_pkg::*;
    logic ref_clk = 0, pad_rst_n = 0;
    wire cfg_rx, cfg_tx;
    logic core_rx = 1;
    wire core_tx;
    tri avdd, avss, dvdd, dvss, dvdd_drv, dvss_drv;
    assign avdd = 1; assign dvdd = 1; assign dvdd_drv = 1;
    assign avss = 0; assign dvss = 0; assign dvss_drv = 0;
    realtime business_bit_ns = 100.0;
    int reset_assertions = 0;
    always #20 ref_clk = ~ref_clk;
    uart_host host(.rx(cfg_rx), .tx(cfg_tx));
    pbit_io_wrapper dut(.pad_clk_i(ref_clk), .pad_rst_n_i(pad_rst_n),
        .pad_uart_rx_i(core_rx), .pad_uart_tx_o(core_tx),
        .pad_pll_cfg_rx_i(cfg_rx), .pad_pll_cfg_tx_o(cfg_tx),
        .pll_avdd(avdd), .pll_avss(avss), .pll_dvdd(dvdd), .pll_dvss(dvss),
        .pll_dvdd_drv(dvdd_drv), .pll_dvss_drv(dvss_drv));
    always @(negedge dut.core_rst_n) reset_assertions++;
    task automatic cfg(input logic [31:0] request, expected);
        logic [31:0] reply;
        host.transfer4(request, reply);
        if (reply !== expected) $fatal(1, "Wrapper cfg req=%h reply=%h expected=%h",request,reply,expected);
    endtask
    task automatic check_period(input realtime expected);
        realtime t0, measured;
        @(posedge dut.core_clk); t0 = $realtime;
        repeat (100) @(posedge dut.core_clk);
        measured = ($realtime-t0)/100.0;
        if (measured < expected-0.005 || measured > expected+0.005)
            $fatal(1, "PLL clock period %0.4f expected %0.4f ns",measured,expected);
        $display("[PLL_WRAPPER] core_period_ns=%0.4f",measured);
    endtask
    task automatic send_core(input logic [7:0] v);
        core_rx = 0; #(business_bit_ns);
        for (int b=0;b<8;b++) begin core_rx=v[b]; #(business_bit_ns); end
        core_rx=1; #(business_bit_ns);
    endtask
    task automatic recv_core(output logic [7:0] v);
        @(negedge core_tx); #(business_bit_ns*1.5);
        for (int b=0;b<8;b++) begin v[b]=core_tx; #(business_bit_ns); end
        if (core_tx !== 1) $fatal(1,"Business UART stop error");
        #(business_bit_ns*0.5);
    endtask
    task automatic core_access(input bit wr, input logic [15:0] addr,
                               input logic [31:0] data, output logic [31:0] value);
        logic [55:0] request, reply;
        request = {wr ? 8'h01 : 8'h02, addr, data};
        fork
            begin for(int b=6;b>=0;b--) send_core(request[b*8+:8]); end
            begin for(int b=6;b>=0;b--) recv_core(reply[b*8+:8]); end
        join
        if (reply[55:48] !== 0 || reply[47:32] !== addr)
            $fatal(1,"Business UART response %h addr=%h",reply,addr);
        if (wr && reply[31:0] !== 0) $fatal(1,"Nonzero write response");
        value = reply[31:0];
        #(business_bit_ns*2);
    endtask
    task automatic wr(input logic [15:0] addr, input logic [31:0] value);
        logic [31:0] unused;
        core_access(1,addr,value,unused);
    endtask
    task automatic rd(input logic [15:0] addr, input logic [31:0] expected);
        logic [31:0] actual;
        core_access(0,addr,0,actual);
        if(actual !== expected) $fatal(1,"Read addr=%h actual=%h expected=%h",addr,actual,expected);
    endtask
    task automatic core_smoke;
        logic [31:0] node_target, node_cfg, edge_target, cmd, value;
        int flat_idx, page_idx, word_idx, bit_idx;
        rd(A_ARRAY_PARAM,{N_SPIN_WIDTH'(N_SPIN),COLS_WIDTH'(COLS),ROWS_WIDTH'(ROWS)});
        node_target = (32'(ROWS-1) << NODE_TARGET_ROW_LSB) |
                      (32'(COLS-1) << NODE_TARGET_COL_LSB) | TARGET_MODE_LOCAL;
        wr(A_NODE_TARGET,node_target); rd(A_NODE_TARGET,node_target);
        // Last physical node is initialized and clamped high.
        node_cfg = (1 << INIT_VALID_LSB) | (1 << CLAMP_VALID_LSB) |
                   (1 << BIAS_VALID_LSB) | (1 << NODE_CFG_INIT_SPIN_LSB) |
                   (1 << NODE_CFG_CLAMP_EN_LSB) | (1 << NODE_CFG_CLAMP_SPIN_LSB);
        wr(A_NODE_CFG,node_cfg); wr(A_NODE_CMD,1 << APPLY_CFG_LSB);
        wr(A_NODE_CMD,1 << READBACK_CFG_LSB); rd(A_NODE_RDATA_CFG,7);
        // Highest shared tile seed address, distinct from physical node target.
        wr(A_NODE_TARGET,(32'(SHARED_ROWS-1)<<NODE_TARGET_ROW_LSB) |
                         (32'(SHARED_COLS-1)<<NODE_TARGET_COL_LSB) | TARGET_MODE_LOCAL);
        wr(A_NODE_SEED,32'h13579bdf); wr(A_NODE_CMD,1 << APPLY_SEED_LSB);
        wr(A_NODE_CMD,1 << READBACK_SEED_LSB); rd(A_NODE_RDATA_SEED,32'h13579bdf);
        edge_target = (32'(ROWS-1)<<EDGE_TARGET_ROW_LSB) |
                      (32'(COLS-2)<<EDGE_TARGET_COL_LSB) | EDGE_TYPE_EDGE_H;
        wr(A_EDGE_TARGET,edge_target); wr(A_EDGE_CFG,32'h157);
        wr(A_EDGE_CMD,1 << APPLY_EDGE_LSB); wr(A_EDGE_CMD,1 << READBACK_EDGE_LSB);
        rd(A_EDGE_RDATA,32'h157);
        // Read the last physical spin through the actual UART snapshot paging.
        flat_idx = (ROWS-1)*COLS + COLS-1;
        page_idx = flat_idx / SNAPSHOT_WIDTH;
        word_idx = (flat_idx / 32) % SPIN_RDATA_REG_NUM;
        bit_idx = flat_idx % 32;
        wr(A_SNAPSHOT_ADDR,32'(page_idx));
        cmd = 0; cmd[SNAPSHOT_LATCH_LSB] = 1;
        wr(A_GLOBAL_CTRL,cmd);
        core_access(0,A_SPIN_RDATA0+16'(4*word_idx),0,value);
        if(value[bit_idx] !== 1) $fatal(1,"Last-node snapshot mismatch");
        $display("[PLL_WRAPPER] core read/write/snapshot PASS array=%0dx%0d",ROWS,COLS);
    endtask
    initial begin
        #400; @(negedge ref_clk); pad_rst_n = 1;
        #1000;
        if(dut.pll_en !== 0 || dut.core_rst_n !== 0) $fatal(1,"Core enabled before APPLY");
        // Bounded local integration check, explicitly NOT the full regression.
        // Finish during the APPLY reply; full serial replies are covered separately.
        if ($test$plusargs("STARTUP_ONLY")) begin
            fork
                begin
                    logic [31:0] unused;
                    host.transfer4(32'h0102_0001, unused);
                end
                begin
                    realtime enable_time;
                    @(posedge dut.pll_en); enable_time = $realtime;
                    @(posedge dut.core_rst_n);
                    if ($realtime-enable_time < 15000.0)
                        $fatal(1,"Core released before 15 us startup wait");
                    check_period(2.5);
                    $display("[TB_PLL_WRAPPER_STARTUP_ONLY] PASS array=%0dx%0d banks=%0d",ROWS,COLS,TANH_BANK_NUM);
                    $finish;
                end
            join
        end
        cfg(32'h0204_0000,32'h0004_0000);
        cfg(32'h0200_0000,32'h0000_0220);
        cfg(32'h0102_0001,32'h0002_0000);
        cfg(32'h0204_0000,32'h0004_0072);
        check_period(2.5); core_smoke();
        // Changing PLL frequency resets the core but not the configuration UART.
        cfg(32'h0100_0218,32'h0000_0000);
        begin : reconfigure
            int old_resets;
            old_resets=reset_assertions;
            cfg(32'h0102_0001,32'h0002_0000);
            if(reset_assertions <= old_resets) $fatal(1,"APPLY did not reset running core");
        end
        cfg(32'h0204_0000,32'h0004_0072);
        cfg(32'h0206_0000,32'h0006_0218);
        check_period(10.0/3.0);
        // Business divider remains 40: 300 MHz / 40 = 7.5 Mbps.
        business_bit_ns=400.0/3.0; core_smoke();
        cfg(32'h0100_0a20,32'h0000_0000);
        cfg(32'h0102_0001,32'h0002_0000);
        cfg(32'h0204_0000,32'h0004_007a);
        check_period(40.0);
        business_bit_ns=1600.0;
        rd(A_ARRAY_PARAM,{N_SPIN_WIDTH'(N_SPIN),COLS_WIDTH'(COLS),ROWS_WIDTH'(ROWS)});
        cfg(32'h0100_0220,32'h0000_0000);
        cfg(32'h0102_0001,32'h0002_0000);
        cfg(32'h0204_0000,32'h0004_0072);
        check_period(2.5);
        $display("[TB_PLL_WRAPPER] PASS array=%0dx%0d banks=%0d",ROWS,COLS,TANH_BANK_NUM);
        $finish;
    end
    initial begin #100_000_000; $fatal(1,"Wrapper watchdog timeout"); end
endmodule
