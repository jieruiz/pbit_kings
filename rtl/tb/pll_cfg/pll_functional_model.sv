// SIMULATION ONLY. Ideal configurable clock with no analog lock, jitter,
// startup transient, supply sensitivity, or PVT behavior.
// Replace this module with the vendor Verilog model for IP-level simulation.
module PLL_TOP(
    inout  wire       AVDD,
    inout  wire       AVSS,
    inout  wire       DVDD,
    inout  wire       DVSS,
    inout  wire       DVDD_DRV,
    inout  wire       DVSS_DRV,
    input  wire       REFCLK,
    input  wire       EN,
    input  wire       BP,
    input  wire [7:0] N,
    input  wire       SELECT,
    input  wire [1:0] OD,
    output wire       CKOUT1,
    output wire       CKOUT2,
    output wire       CKTST
);
    timeunit 1ns;
    timeprecision 1ps;

    realtime last_ref = 0.0;
    realtime ref_period = 40.0;
    realtime half_period;
    logic osc = 1'b0;

    initial
        $display("[PLL_MODEL] ideal digital model; no lock, jitter, PVT, or supply behavior");

    always @(posedge REFCLK) begin
        if (last_ref > 0.0)
            ref_period = $realtime - last_ref;
        last_ref = $realtime;
    end

    initial begin
        forever begin
            wait (EN === 1'b1);
            while (EN === 1'b1) begin
                if (N == 0)
                    $fatal(1, "PLL functional model received N=0");
                half_period = ref_period * (1 << OD) /
                              (2.0 * N * (SELECT ? 2 : 1));
                #(half_period);
                if (EN === 1'b1)
                    osc = ~osc;
            end
            osc = 1'b0;
        end
    end

    assign CKOUT1 = EN ? (BP ? REFCLK : osc) : 1'b0;
    assign CKOUT2 = 1'b0;
    assign CKTST = 1'b0;
endmodule
