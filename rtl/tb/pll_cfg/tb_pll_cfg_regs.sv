module tb_pll_cfg_regs;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk = 0, rst_n = 0, req_valid = 0, req_write = 0;
    logic [7:0] addr = 0;
    logic [15:0] data = 0;
    logic core_rst_n = 0;
    wire resp_valid, pll_en, core_release, pll_select, pll_bp;
    wire [7:0] status, pll_n;
    wire [15:0] resp_data;
    wire [1:0] pll_od;
    int accepted = 0, rejected = 0;
    always #20 clk = ~clk;
    // Short controller waits ONLY in this unit test; UART/wrapper use production waits.
    pll_cfg_regs #(.WAIT_CYCLES(5), .RELEASE_TIMEOUT(8)) dut(
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_write(req_write),
        .req_addr(addr), .req_data(data), .resp_valid(resp_valid),
        .resp_status(status), .resp_data(resp_data), .core_rst_n(core_rst_n),
        .pll_en(pll_en), .core_release(core_release), .pll_n(pll_n),
        .pll_select(pll_select), .pll_bp(pll_bp), .pll_od(pll_od));
    task automatic reset_dut;
        @(negedge clk); rst_n = 0; req_valid = 0; core_rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
    endtask
    task automatic access_reg(input bit wr, input logic [7:0] a,
        input logic [15:0] d, input logic [7:0] expected_status,
        output logic [15:0] reply);
        @(negedge clk); req_valid = 1; req_write = wr; addr = a; data = d;
        @(posedge clk); #1;
        if (resp_valid !== 1 || status !== expected_status)
            $fatal(1, "PLL REG addr=%h data=%h status=%h expected=%h", a,d,status,expected_status);
        reply = resp_data;
        @(negedge clk); req_valid = 0;
    endtask
    initial begin : tests
        logic [15:0] reply;
        int n, vco_mhz, expected_error;
        // Independent integer-MHz oracle for every 12-bit configuration.
        for (int cfg = 0; cfg < 4096; cfg++) begin
            reset_dut();
            n = cfg & 255;
            vco_mhz = 25 * n * (((cfg >> 8) & 1) ? 2 : 1);
            expected_error = 0;
            if (n < 17 || vco_mhz < 500 || vco_mhz > 1200) expected_error = 3;
            else if (!(cfg & 2048) && vco_mhz > (400 << ((cfg >> 9) & 3))) expected_error = 4;
            access_reg(1, 0, 16'(cfg), 0, reply);
            access_reg(1, 2, 1, expected_error ? 2 : 0, reply);
            if (expected_error) begin
                rejected++;
                access_reg(0, 4, 0, 0, reply);
                if (reply !== ((expected_error << 8) | 4)) $fatal(1, "Config error mismatch cfg=%h status=%h", cfg,reply);
                if (pll_en || core_release) $fatal(1, "Rejected config changed enable");
            end else begin
                accepted++;
                wait(core_release); @(negedge clk); core_rst_n = 1;
                repeat (5) @(negedge clk);
                access_reg(0, 6, 0, 0, reply);
                if (reply !== 16'(cfg)) $fatal(1, "ACTIVE mismatch");
                access_reg(0, 4, 0, 0, reply);
                if (reply !== ((cfg & 2048) ? 16'h007a : 16'h0072)) $fatal(1, "Completion mismatch");
            end
        end
        // Serial protocol cannot naturally hit this short BUSY interval;
        // exercise the register interface directly, including atomic APPLY.
        reset_dut();
        access_reg(1, 2, 1, 0, reply);
        access_reg(1, 0, 16'h0218, 3, reply);
        access_reg(1, 2, 1, 3, reply);
        repeat (30) @(negedge clk);
        access_reg(0, 4, 0, 0, reply);
        if (reply !== 16'h0734 || core_release || !pll_en)
            $fatal(1, "Missing reset feedback must time out, status=%h",reply);
        access_reg(0, 6, 0, 0, reply);
        if (reply !== 16'h0220) $fatal(1, "BUSY write changed pending/active config");
        access_reg(1, 2, 2, 0, reply);
        access_reg(1, 2, 1, 0, reply);
        wait(core_release); @(negedge clk); core_rst_n = 1;
        repeat (6) @(negedge clk);
        access_reg(0, 4, 0, 0, reply);
        if (reply !== 16'h0072) $fatal(1, "Retry after timeout failed");
        $display("[TB_PLL_CFG_REGS] PASS configurations=4096 accepted=%0d rejected=%0d",accepted,rejected);
        $finish;
    end
    initial begin #30_000_000; $fatal(1,"PLL register watchdog timeout"); end
endmodule
