`timescale 1ns/1ps
import pbit_pkg::*;

// Exhaustive 7-bit boundary regression for edge <= and bias < semantics.
module tb_probability_modes;
    logic clk = 1'b0;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_rand = '0;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_direct = '0;
    logic edge_valid_direct = 1'b0;
    wire edge_accept_direct;

    logic [SEED_WIDTH-1:0] rnd32 = '0;
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign = 1'b1;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob = '0;
    logic [MAC_EDGE_NUM-1:0] neighbor_spin = '0;
    logic [MAC_EDGE_NUM-1:0] edge_valid = '0;
    logic [MAC_EDGE_NUM-1:0] edge_sign = '0;
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob [0:MAC_EDGE_NUM-1];
    logic macsum_en = 1'b0;
    wire signed [MACSUM_WIDTH-1:0] macsum;

    integer probability_code;
    integer random_value;
    integer lane;
    integer edge_accept_count;
    integer bias_accept_count;

    always #1 clk = ~clk;

    edge_prob_compare #(
        .WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) u_edge_prob_compare (
        .rand_i   (edge_rand),
        .prob_i   (edge_prob_direct),
        .valid_i  (edge_valid_direct),
        .accept_o (edge_accept_direct)
    );

    mac u_mac (
        .clk             (clk),
        .rnd32_i         (rnd32),
        .bias_sign_i     (bias_sign),
        .bias_prob_i     (bias_prob),
        .neighbor_spin_i (neighbor_spin),
        .edge_valid_i    (edge_valid),
        .edge_sign_i     (edge_sign),
        .edge_prob_i     (edge_prob),
        .macsum_en_i     (macsum_en),
        .macsum_o        (macsum)
    );

    task automatic set_bias_random(input integer value);
        begin
            rnd32 = '0;
            rnd32[0]  = value[0];
            rnd32[2]  = value[1];
            rnd32[4]  = value[2];
            rnd32[6]  = value[3];
            rnd32[8]  = value[4];
            rnd32[10] = value[5];
            rnd32[12] = value[6];
        end
    endtask

    task automatic check_mac_result(
        input integer probability,
        input integer random_number,
        input integer expected_sum
    );
        begin
            @(negedge clk);
            bias_prob = probability;
            set_bias_random(random_number);
            macsum_en = 1'b1;
            @(posedge clk);
            #0.001;
            if ($signed(macsum) != expected_sum)
                $fatal(1,
                    "Bias MAC mismatch prob=%0d rand=%0d actual=%0d expected=%0d",
                    probability, random_number, $signed(macsum), expected_sum);
            @(negedge clk);
            macsum_en = 1'b0;
        end
    endtask

    initial begin
        for (lane = 0; lane < MAC_EDGE_NUM; lane = lane + 1)
            edge_prob[lane] = '0;

        for (probability_code = 0; probability_code < 128;
             probability_code = probability_code + 1) begin
            edge_accept_count = 0;
            bias_accept_count = 0;
            edge_prob_direct = probability_code;
            bias_prob = probability_code;

            for (random_value = 0; random_value < 128;
                 random_value = random_value + 1) begin
                edge_rand = random_value;
                edge_valid_direct = 1'b1;
                set_bias_random(random_value);
                #0.001;

                if (edge_accept_direct !== (random_value <= probability_code))
                    $fatal(1,
                        "Edge comparison mismatch prob=%0d rand=%0d actual=%b",
                        probability_code, random_value, edge_accept_direct);
                if (u_mac.accept_bias_w !== (random_value < probability_code))
                    $fatal(1,
                        "Bias comparison mismatch prob=%0d rand=%0d actual=%b",
                        probability_code, random_value, u_mac.accept_bias_w);
                if (edge_accept_direct)
                    edge_accept_count = edge_accept_count + 1;
                if (u_mac.accept_bias_w)
                    bias_accept_count = bias_accept_count + 1;
            end

            if (edge_accept_count != probability_code + 1)
                $fatal(1, "Edge acceptance count mismatch code=%0d count=%0d",
                       probability_code, edge_accept_count);
            if (bias_accept_count != probability_code)
                $fatal(1, "Bias acceptance count mismatch code=%0d count=%0d",
                       probability_code, bias_accept_count);

            edge_valid_direct = 1'b0;
            edge_rand = '0;
            #0.001;
            if (edge_accept_direct !== 1'b0)
                $fatal(1, "Edge valid gating failed code=%0d", probability_code);
        end

        // Black-box MAC checks: all six edge contributions remain disabled.
        check_mac_result(0,   0,   0);
        check_mac_result(1,   0,   1);
        check_mac_result(1,   1,   0);
        check_mac_result(127, 126, 1);
        check_mac_result(127, 127, 0);

        $display("[TB_PROBABILITY_MODES] PASS edge_count=code+1 bias_count=code valid_zero=0");
        $finish;
    end
endmodule
