// SIMULATION ONLY. Ideal configurable clock, no analog startup/lock/jitter model.
// Can be replaced by the vendor functional model via PLL_SIM_MODEL in run_sim_sbatch.sh.
module PLL_TOP(inout wire AVDD, AVSS, DVDD, DVSS, DVDD_DRV, DVSS_DRV,
    input wire REFCLK, EN, BP, SELECT, input wire [7:0] N, input wire [1:0] OD,
    output wire CKOUT1, CKOUT2, CKTST);
    timeunit 1ns;
    timeprecision 1ps;
    realtime last_ref = 0, ref_period = 40.0, half_period;
    logic osc = 0;
    always @(posedge REFCLK) begin
        if (last_ref > 0) ref_period = $realtime - last_ref;
        last_ref = $realtime;
    end
    initial forever begin
        wait(EN === 1'b1);
        while (EN === 1'b1) begin
            if (N == 0) $fatal(1, "PLL model: zero divider");
            half_period = ref_period * (1 << OD) / (2.0 * N * (SELECT ? 2 : 1));
            #(half_period);
            if (EN === 1'b1) osc = ~osc;
        end
        osc = 0;
    end
    assign CKOUT1 = EN ? (BP ? REFCLK : osc) : 1'b0;
    assign CKOUT2 = 1'b0;
    assign CKTST = 1'b0;
endmodule
