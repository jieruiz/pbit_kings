module tb_pll_cfg_uart;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk = 0, rst_n = 0;
    wire rx, tx, req_valid, req_write, resp_valid;
    wire [7:0] addr, status, pll_n;
    wire [15:0] data, resp_data;
    wire pll_en, core_release, pll_select, pll_bp;
    wire [1:0] pll_od;
    logic core_clk = 0;
    wire core_rst_n;
    always #20 clk = ~clk;
    always #1.25 core_clk = ~core_clk;
    uart_host host(.rx(rx), .tx(tx));
    // No baud override: catch accidental use of the business UART baud rate.
    pll_cfg_uart dut_uart(.clk(clk), .rst_n(rst_n), .rx_i(rx), .tx_o(tx),
        .req_valid(req_valid), .req_write(req_write), .req_addr(addr), .req_data(data),
        .resp_valid(resp_valid), .resp_status(status), .resp_data(resp_data));
    pll_cfg_regs dut_regs(.clk(clk), .rst_n(rst_n), .req_valid(req_valid),
        .req_write(req_write), .req_addr(addr), .req_data(data),
        .resp_valid(resp_valid), .resp_status(status), .resp_data(resp_data),
        .core_rst_n(core_rst_n), .pll_en(pll_en), .core_release(core_release),
        .pll_n(pll_n), .pll_select(pll_select), .pll_bp(pll_bp), .pll_od(pll_od));
    reset_sync_async_assert reset_feedback(.clk_i(core_clk),
        .arst_n_i(rst_n & core_release), .rst_n_o(core_rst_n));
    task automatic check(input logic [31:0] request, expected);
        logic [31:0] reply;
        host.transfer4(request, reply);
        if (reply !== expected)
            $fatal(1, "PLL UART req=%08h reply=%08h expected=%08h", request, reply, expected);
    endtask
    initial begin
        #200; @(negedge clk); rst_n = 1;
        #200;
        check(32'h0200_0000, 32'h0000_0220);
        check(32'h0206_0000, 32'h0006_0220);
        check(32'h0204_0000, 32'h0004_0000);
        check(32'h0202_0000, 32'h0002_0000);
        if (pll_en || core_rst_n) $fatal(1, "Core started without APPLY");
        check(32'hff00_0000, 32'h0100_0000);
        check(32'h0201_0000, 32'h0201_0000);
        check(32'h0204_0000, 32'h0004_0104);
        check(32'h0106_0220, 32'h0206_0000);
        check(32'h0102_0003, 32'h0202_0000);
        check(32'h0204_0000, 32'h0004_0504);
        check(32'h0102_0002, 32'h0002_0000);
        // Invalid shadow is writable, but invalid APPLY must not affect ACTIVE.
        check(32'h0100_1220, 32'h0000_0000);
        check(32'h0102_0001, 32'h0202_0000);
        check(32'h0204_0000, 32'h0004_0204);
        check(32'h0206_0000, 32'h0006_0220);
        if (pll_en || core_rst_n) $fatal(1, "Invalid APPLY started the core");
        check(32'h0100_0220, 32'h0000_0000);
        check(32'h0102_0002, 32'h0002_0000);
        check(32'h0102_0001, 32'h0002_0000);
        check(32'h0204_0000, 32'h0004_0072);
        if (!pll_en || !core_rst_n) $fatal(1, "Valid APPLY did not start core");
        // Timeout is tested at its production 20 ms value, without shortening it.
        host.send_byte(8'h01); host.send_byte(8'h00);
        #21_000_000;
        check(32'h0200_0000, 32'h0000_0220);
        $display("[TB_PLL_CFG_UART] PASS baud=115200 ref_hz=25000000 timeout_ms=20");
        $finish;
    end
    initial begin #100_000_000; $fatal(1, "PLL UART watchdog timeout"); end
endmodule
