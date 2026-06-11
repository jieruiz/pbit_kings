`timescale 1ns / 1ps

module tb_tanh_lut_comb;

    reg  [3:0]        i0_level_i;
    reg  signed [4:0] h_i;
    wire [15:0]       p_up_thr_o;

    integer level;
    integer h;

    reg [15:0] p_pos;
    reg [15:0] p_neg;
    reg [15:0] prev_p;
    reg [16:0] sum_sym;

    tanh_lut_comb dut (
        .i0_level_i (i0_level_i),
        .h_i        (h_i),
        .p_up_thr_o (p_up_thr_o)
    );

    task check_exact;
        input [3:0]        level_in;
        input signed [4:0] h_in;
        input [15:0]       expected;
        begin
            i0_level_i = level_in;
            h_i        = h_in;
            #1;

            if (p_up_thr_o !== expected) begin
                $display("ERROR exact: level=%0d h=%0d expected=%h got=%h",
                         level_in, h_in, expected, p_up_thr_o);
                $stop;
            end else begin
                $display("PASS exact : level=%0d h=%0d p=%h",
                         level_in, h_in, p_up_thr_o);
            end
        end
    endtask

    task get_lut_value;
        input  [3:0]        level_in;
        input  signed [4:0] h_in;
        output [15:0]       value_out;
        begin
            i0_level_i = level_in;
            h_i        = h_in;
            #1;
            value_out  = p_up_thr_o;
        end
    endtask

    initial begin
        $display("========================================");
        $display("Start tb_tanh_lut_comb");
        $display("========================================");

        i0_level_i = 4'd0;
        h_i        = 5'sd0;
        #5;

        // ------------------------------------------------------------
        // 1. Exact value tests
        // ------------------------------------------------------------

        check_exact(4'd0,  5'sd0,  16'h8000);
        check_exact(4'd0,  5'sd1,  16'hBB26);
        check_exact(4'd0, -5'sd1,  16'h44D9);
        check_exact(4'd0,  5'sd2,  16'hE17B);
        check_exact(4'd0, -5'sd2,  16'h1E84);
        check_exact(4'd0,  5'sd8,  16'hFFE9);
        check_exact(4'd0, -5'sd8,  16'h0016);
        check_exact(4'd0,  5'sd9,  16'hFFF7);
        check_exact(4'd0, -5'sd9,  16'h0008);

        check_exact(4'd1,  5'sd0,  16'h8000);
        check_exact(4'd1,  5'sd1,  16'hE4E3);
        check_exact(4'd1, -5'sd1,  16'h1B1C);
        check_exact(4'd1,  5'sd2,  16'hFC74);
        check_exact(4'd1, -5'sd2,  16'h038B);

        check_exact(4'd2,  5'sd0,  16'h8000);
        check_exact(4'd2,  5'sd1,  16'hF698);
        check_exact(4'd2, -5'sd1,  16'h0967);
        check_exact(4'd2,  5'sd2,  16'hFFA0);
        check_exact(4'd2, -5'sd2,  16'h005F);

        check_exact(4'd15,  5'sd0,  16'h8000);
        check_exact(4'd15,  5'sd1,  16'hFFFF);
        check_exact(4'd15, -5'sd1,  16'h0000);

        // ------------------------------------------------------------
        // 2. Check h = 0 for all I0 levels
        // ------------------------------------------------------------

        for (level = 0; level < 16; level = level + 1) begin
            get_lut_value(level[3:0], 5'sd0, p_pos);

            if (p_pos !== 16'h8000) begin
                $display("ERROR h=0: level=%0d expected=8000 got=%h",
                         level, p_pos);
                $stop;
            end
        end

        $display("PASS: h=0 gives 0x8000 for all levels");

        // ------------------------------------------------------------
        // 3. Check symmetry:
        //    p(-h) = 16'hFFFF - p(+h), for h = 1 ... 9
        // ------------------------------------------------------------

        for (level = 0; level < 16; level = level + 1) begin
            for (h = 1; h <= 9; h = h + 1) begin
                get_lut_value(level[3:0],  h[4:0], p_pos);
                get_lut_value(level[3:0], -h[4:0], p_neg);

                sum_sym = {1'b0, p_pos} + {1'b0, p_neg};

                if (sum_sym !== 17'h0FFFF) begin
                    $display("ERROR symmetry: level=%0d h=%0d p_pos=%h p_neg=%h sum=%h",
                             level, h, p_pos, p_neg, sum_sym);
                    $stop;
                end
            end
        end

        $display("PASS: symmetry check passed");

        // ------------------------------------------------------------
        // 4. Check monotonicity for positive h:
        //    p(h+1) >= p(h)
        // ------------------------------------------------------------

        for (level = 0; level < 16; level = level + 1) begin
            get_lut_value(level[3:0], 5'sd0, prev_p);

            for (h = 1; h <= 9; h = h + 1) begin
                get_lut_value(level[3:0], h[4:0], p_pos);

                if (p_pos < prev_p) begin
                    $display("ERROR monotonic positive: level=%0d h=%0d prev=%h current=%h",
                             level, h, prev_p, p_pos);
                    $stop;
                end

                prev_p = p_pos;
            end
        end

        $display("PASS: positive monotonicity check passed");

        // ------------------------------------------------------------
        // 5. Check monotonicity for negative h:
        //    as h goes from -9 to 0, p should increase
        // ------------------------------------------------------------

        for (level = 0; level < 16; level = level + 1) begin
            get_lut_value(level[3:0], -5'sd9, prev_p);

            for (h = -8; h <= 0; h = h + 1) begin
                get_lut_value(level[3:0], h[4:0], p_pos);

                if (p_pos < prev_p) begin
                    $display("ERROR monotonic negative: level=%0d h=%0d prev=%h current=%h",
                             level, h, prev_p, p_pos);
                    $stop;
                end

                prev_p = p_pos;
            end
        end

        $display("PASS: negative monotonicity check passed");

        $display("========================================");
        $display("tb_tanh_lut_comb PASS");
        $display("========================================");

        $finish;
    end

endmodule
