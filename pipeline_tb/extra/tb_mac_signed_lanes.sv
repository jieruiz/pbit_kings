`timescale 1ns/1ps
import pbit_pkg::*;

// Signed contribution and pipeline regression for all six MAC edge lanes.
module tb_mac_signed_lanes;
    logic clk = 1'b0;
    logic [SEED_WIDTH-1:0] rnd32 = '0;
    logic bias_sign = 1'b0;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob = '0;
    logic [MAC_EDGE_NUM-1:0] neighbor_spin = '0;
    logic [MAC_EDGE_NUM-1:0] edge_valid = '0;
    logic [MAC_EDGE_NUM-1:0] edge_sign = '0;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob [0:MAC_EDGE_NUM-1];
    logic contrib_en = 1'b0;
    logic macsum_en = 1'b0;
    wire signed [MACSUM_WIDTH-1:0] macsum;

    always #1 clk = ~clk;

    mac dut (
        .clk(clk), .rnd32_i(rnd32),
        .bias_sign_i(bias_sign), .bias_prob_i(bias_prob),
        .neighbor_spin_i(neighbor_spin), .edge_valid_i(edge_valid),
        .edge_sign_i(edge_sign), .edge_prob_i(edge_prob),
        .contrib_en_i(contrib_en), .macsum_en_i(macsum_en),
        .macsum_o(macsum)
    );

    task automatic capture_and_check(input integer expected, input string label);
        begin
            @(negedge clk);
            contrib_en = 1'b1;
            @(posedge clk);
            #0.001;
            @(negedge clk);
            contrib_en = 1'b0;

            // Stage 2 must consume the registered contribution, not live inputs.
            edge_valid = '0;
            edge_sign = '0;
            neighbor_spin = '0;
            bias_prob = '0;
            rnd32 = '1;
            macsum_en = 1'b1;
            @(posedge clk);
            #0.001;
            if ($signed(macsum) !== expected)
                $fatal(1, "%s actual=%0d expected=%0d", label,
                       $signed(macsum), expected);
            @(negedge clk);
            macsum_en = 1'b0;
            rnd32 = '0;
        end
    endtask

    initial begin : TEST
        integer lane;
        integer sign_value;
        integer spin_value;
        integer expected;

        for (lane = 0; lane < MAC_EDGE_NUM; lane++) edge_prob[lane] = '0;

        // With rand=prob=0, edge <= accepts. Check every signed truth-table
        // combination independently on every physical lane.
        for (lane = 0; lane < MAC_EDGE_NUM; lane++) begin
            for (sign_value = 0; sign_value < 2; sign_value++) begin
                for (spin_value = 0; spin_value < 2; spin_value++) begin
                    edge_valid = '0;
                    edge_sign = '0;
                    neighbor_spin = '0;
                    edge_valid[lane] = 1'b1;
                    edge_sign[lane] = sign_value[0];
                    neighbor_spin[lane] = spin_value[0];
                    expected = (sign_value == spin_value) ? 1 : -1;
                    capture_and_check(expected,
                        $sformatf("lane=%0d sign=%0d spin=%0d", lane,
                                  sign_value, spin_value));
                end
            end
        end

        // A disabled edge contributes zero even at the inclusive equality point.
        edge_valid = '0;
        edge_sign = '1;
        neighbor_spin = '1;
        capture_and_check(0, "all edge valids clear");

        // Concurrent tree check: +1,-1,+1,-1,+1,-1 plus positive bias = +1.
        edge_valid = '1;
        edge_sign = 6'b101010;
        neighbor_spin = 6'b111111;
        bias_sign = 1'b1;
        bias_prob = 7'd1;
        capture_and_check(1, "balanced six lanes plus positive bias");

        // Reverse all edge signs and the bias sign: total must be -1.
        edge_valid = '1;
        edge_sign = 6'b010101;
        neighbor_spin = 6'b111111;
        bias_sign = 1'b0;
        bias_prob = 7'd1;
        capture_and_check(-1, "balanced six lanes plus negative bias");

        $display("[TB_MAC_SIGNED_LANES] PASS all six lanes, signs, valid and pipeline hold");
        $finish;
    end
endmodule
