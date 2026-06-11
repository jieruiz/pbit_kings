`timescale 1ns / 1ps

module tb_pbit_update_core_named;

    reg clk;
    reg rst_n;

    reg        load_seed_i;
    reg [31:0] seed_i;

    reg        init_spin_we_i;
    reg        init_spin_i;

    // ------------------------------------------------------------
    // Added for clamp version of pbit_update_core_named
    // ------------------------------------------------------------
    reg        clamp_en_i;
    reg        clamp_spin_i;
    reg        bias_sign_i;
    reg [3:0]  bias_prob4_i;

    reg        start_i;
    reg [3:0]  i0_level_i;

    reg neighbor_spin_n_i;
    reg neighbor_spin_ne_i;
    reg neighbor_spin_e_i;
    reg neighbor_spin_se_i;
    reg neighbor_spin_s_i;
    reg neighbor_spin_sw_i;
    reg neighbor_spin_w_i;
    reg neighbor_spin_nw_i;

    reg edge_valid_n_i;
    reg edge_valid_ne_i;
    reg edge_valid_e_i;
    reg edge_valid_se_i;
    reg edge_valid_s_i;
    reg edge_valid_sw_i;
    reg edge_valid_w_i;
    reg edge_valid_nw_i;

    reg edge_sign_n_i;
    reg edge_sign_ne_i;
    reg edge_sign_e_i;
    reg edge_sign_se_i;
    reg edge_sign_s_i;
    reg edge_sign_sw_i;
    reg edge_sign_w_i;
    reg edge_sign_nw_i;

    reg [3:0] edge_prob_n_i;
    reg [3:0] edge_prob_ne_i;
    reg [3:0] edge_prob_e_i;
    reg [3:0] edge_prob_se_i;
    reg [3:0] edge_prob_s_i;
    reg [3:0] edge_prob_sw_i;
    reg [3:0] edge_prob_w_i;
    reg [3:0] edge_prob_nw_i;

    wire       spin_o;
    wire       busy_o;
    wire       done_o;
    wire       flip_o;

    wire signed [4:0] dbg_h_i_o;
    wire [3:0]        dbg_plus_count_o;
    wire [31:0]       dbg_edge_rand32_o;
    wire [15:0]       dbg_pbit_rand16_o;
    wire [7:0]        dbg_edge_accept_o;

    integer error_count;

    pbit_update_core_named #(
        .N_TRIAL(5)
    ) dut (
        .clk                 (clk),
        .rst_n               (rst_n),

        .load_seed_i         (load_seed_i),
        .seed_i              (seed_i),

        .init_spin_we_i      (init_spin_we_i),
        .init_spin_i         (init_spin_i),

        // --------------------------------------------------------
        // Added clamp ports
        // --------------------------------------------------------
        .clamp_en_i          (clamp_en_i),
        .clamp_spin_i        (clamp_spin_i),
        .bias_sign_i         (bias_sign_i),
        .bias_prob4_i        (bias_prob4_i),

        .start_i             (start_i),
        .i0_level_i          (i0_level_i),

        .neighbor_spin_n_i   (neighbor_spin_n_i),
        .neighbor_spin_ne_i  (neighbor_spin_ne_i),
        .neighbor_spin_e_i   (neighbor_spin_e_i),
        .neighbor_spin_se_i  (neighbor_spin_se_i),
        .neighbor_spin_s_i   (neighbor_spin_s_i),
        .neighbor_spin_sw_i  (neighbor_spin_sw_i),
        .neighbor_spin_w_i   (neighbor_spin_w_i),
        .neighbor_spin_nw_i  (neighbor_spin_nw_i),

        .edge_valid_n_i      (edge_valid_n_i),
        .edge_valid_ne_i     (edge_valid_ne_i),
        .edge_valid_e_i      (edge_valid_e_i),
        .edge_valid_se_i     (edge_valid_se_i),
        .edge_valid_s_i      (edge_valid_s_i),
        .edge_valid_sw_i     (edge_valid_sw_i),
        .edge_valid_w_i      (edge_valid_w_i),
        .edge_valid_nw_i     (edge_valid_nw_i),

        .edge_sign_n_i       (edge_sign_n_i),
        .edge_sign_ne_i      (edge_sign_ne_i),
        .edge_sign_e_i       (edge_sign_e_i),
        .edge_sign_se_i      (edge_sign_se_i),
        .edge_sign_s_i       (edge_sign_s_i),
        .edge_sign_sw_i      (edge_sign_sw_i),
        .edge_sign_w_i       (edge_sign_w_i),
        .edge_sign_nw_i      (edge_sign_nw_i),

        .edge_prob_n_i       (edge_prob_n_i),
        .edge_prob_ne_i      (edge_prob_ne_i),
        .edge_prob_e_i       (edge_prob_e_i),
        .edge_prob_se_i      (edge_prob_se_i),
        .edge_prob_s_i       (edge_prob_s_i),
        .edge_prob_sw_i      (edge_prob_sw_i),
        .edge_prob_w_i       (edge_prob_w_i),
        .edge_prob_nw_i      (edge_prob_nw_i),

        .spin_o              (spin_o),
        .busy_o              (busy_o),
        .done_o              (done_o),
        .flip_o              (flip_o),

        .dbg_h_i_o           (dbg_h_i_o),
        .dbg_plus_count_o    (dbg_plus_count_o),
        .dbg_edge_rand32_o   (dbg_edge_rand32_o),
        .dbg_pbit_rand16_o   (dbg_pbit_rand16_o),
        .dbg_edge_accept_o   (dbg_edge_accept_o)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    // ------------------------------------------------------------
    // Utility tasks
    // ------------------------------------------------------------

    task apply_reset;
        begin
            rst_n          = 1'b0;
            load_seed_i    = 1'b0;
            seed_i         = 32'h0000_0000;

            init_spin_we_i = 1'b0;
            init_spin_i    = 1'b0;

            // Important: avoid X/Z clamp input
            clamp_en_i     = 1'b0;
            clamp_spin_i   = 1'b0;
            bias_sign_i    = 1'b1;
            bias_prob4_i   = 4'd0;

            start_i        = 1'b0;
            i0_level_i     = 4'd0;

            set_all_neighbors(1'b1);
            set_all_valid(1'b0);
            set_all_signs(1'b1);
            set_all_probs(4'h0);

            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task load_seed;
        input [31:0] seed_value;
        begin
            @(negedge clk);
            seed_i      = seed_value;
            load_seed_i = 1'b1;

            @(negedge clk);
            load_seed_i = 1'b0;
            seed_i      = 32'h0000_0000;

            @(negedge clk);
        end
    endtask

    task init_spin;
        input spin_value;
        begin
            @(negedge clk);
            init_spin_i    = spin_value;
            init_spin_we_i = 1'b1;

            @(negedge clk);
            init_spin_we_i = 1'b0;
        end
    endtask

    task start_update_and_wait_done;
        integer timeout;
        begin
            @(negedge clk);
            start_i = 1'b1;

            @(negedge clk);
            start_i = 1'b0;

            timeout = 0;

            while ((done_o !== 1'b1) && (timeout < 300)) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end

            if (done_o !== 1'b1) begin
                $display("ERROR: timeout waiting for done_o");
                error_count = error_count + 1;
            end

            #1;
        end
    endtask

    task set_all_neighbors;
        input spin_value;
        begin
            neighbor_spin_n_i  = spin_value;
            neighbor_spin_ne_i = spin_value;
            neighbor_spin_e_i  = spin_value;
            neighbor_spin_se_i = spin_value;
            neighbor_spin_s_i  = spin_value;
            neighbor_spin_sw_i = spin_value;
            neighbor_spin_w_i  = spin_value;
            neighbor_spin_nw_i = spin_value;
        end
    endtask

    task set_all_valid;
        input valid_value;
        begin
            edge_valid_n_i  = valid_value;
            edge_valid_ne_i = valid_value;
            edge_valid_e_i  = valid_value;
            edge_valid_se_i = valid_value;
            edge_valid_s_i  = valid_value;
            edge_valid_sw_i = valid_value;
            edge_valid_w_i  = valid_value;
            edge_valid_nw_i = valid_value;
        end
    endtask

    task set_all_signs;
        input sign_value;
        begin
            edge_sign_n_i  = sign_value;
            edge_sign_ne_i = sign_value;
            edge_sign_e_i  = sign_value;
            edge_sign_se_i = sign_value;
            edge_sign_s_i  = sign_value;
            edge_sign_sw_i = sign_value;
            edge_sign_w_i  = sign_value;
            edge_sign_nw_i = sign_value;
        end
    endtask

    task set_all_probs;
        input [3:0] prob_value;
        begin
            edge_prob_n_i  = prob_value;
            edge_prob_ne_i = prob_value;
            edge_prob_e_i  = prob_value;
            edge_prob_se_i = prob_value;
            edge_prob_s_i  = prob_value;
            edge_prob_sw_i = prob_value;
            edge_prob_w_i  = prob_value;
            edge_prob_nw_i = prob_value;
        end
    endtask

    task check_bit;
        input [255:0] name;
        input got;
        input expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: expected=%b got=%b", name, expected, got);
                error_count = error_count + 1;
            end else begin
                $display("PASS  %0s: got=%b", name, got);
            end
        end
    endtask

    task check_u4;
        input [255:0] name;
        input [3:0] got;
        input [3:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: expected=%0d got=%0d", name, expected, got);
                error_count = error_count + 1;
            end else begin
                $display("PASS  %0s: got=%0d", name, got);
            end
        end
    endtask

    task check_s5;
        input [255:0] name;
        input signed [4:0] got;
        input signed [4:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: expected=%0d got=%0d", name, expected, got);
                error_count = error_count + 1;
            end else begin
                $display("PASS  %0s: got=%0d", name, got);
            end
        end
    endtask

    task check_u8;
        input [255:0] name;
        input [7:0] got;
        input [7:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: expected=%h got=%h", name, expected, got);
                error_count = error_count + 1;
            end else begin
                $display("PASS  %0s: got=%h", name, got);
            end
        end
    endtask

    task check_u16;
        input [255:0] name;
        input [15:0] got;
        input [15:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: expected=%h got=%h", name, expected, got);
                error_count = error_count + 1;
            end else begin
                $display("PASS  %0s: got=%h", name, got);
            end
        end
    endtask

    task check_u32;
        input [255:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: expected=%h got=%h", name, expected, got);
                error_count = error_count + 1;
            end else begin
                $display("PASS  %0s: got=%h", name, got);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------

    initial begin
        error_count = 0;

        $display("=================================================");
        $display("Start tb_pbit_update_core_named");
        $display("=================================================");

        // ============================================================
        // Case 1:
        // All edges invalid.
        // h_i = 0.
        // i0_level = 0, tanh_lut gives p_up = 0x8000.
        // With seed 0x12345678 and current RTL random extraction,
        // proposal votes are expected to have plus_count = 3.
        // Final spin should be +1.
        // ============================================================

        $display("");
        $display("CASE 1: all edges invalid, h_i = 0");

        apply_reset();
        load_seed(32'h1234_5678);

        i0_level_i = 4'd0;
        clamp_en_i = 1'b0;
        clamp_spin_i = 1'b0;

        set_all_valid(1'b0);
        set_all_signs(1'b1);
        set_all_neighbors(1'b1);
        set_all_probs(4'h0);

        init_spin(1'b0);
        start_update_and_wait_done();

        check_s5 ("case1 dbg_h_i_o",        dbg_h_i_o,        5'sd0);
        check_u4 ("case1 plus_count",       dbg_plus_count_o, 4'd3);
        check_bit("case1 final spin_o",     spin_o,           1'b1);
        check_bit("case1 flip_o",           flip_o,           1'b1);
        check_bit("case1 bias_accept",      dut.accept_bias_w, 1'b0);

        check_u32("case1 last edge rand32", dbg_edge_rand32_o, 32'h68AC_F168);
        check_u16("case1 last pbit rand16", dbg_pbit_rand16_o, 16'hDD8D);
        check_u4 ("case1 bias_rand4",       dut.bias_rand4_w,
                  {dut.rnd32_w[8], dut.rnd32_w[6],
                   dut.rnd32_w[4], dut.rnd32_w[2]});

        // ============================================================
        // Case 2:
        // Bias only, bias_sign = 0.
        // bias_prob4 = F forces acceptance.
        // bias contributes -1, so h_i = -(-1) = +1.
        // i0_level=15 makes p_up(+1)=FFFF, so all five votes are 1.
        // ============================================================

        $display("");
        $display("CASE 2: bias only, bias_sign=0, h_i=+1");

        apply_reset();
        load_seed(32'h1234_5678);

        i0_level_i   = 4'd15;
        clamp_en_i   = 1'b0;
        clamp_spin_i = 1'b0;
        bias_sign_i  = 1'b0;
        bias_prob4_i = 4'hF;

        set_all_valid(1'b0);
        set_all_signs(1'b1);
        set_all_neighbors(1'b1);
        set_all_probs(4'h0);

        init_spin(1'b0);
        start_update_and_wait_done();

        check_s5 ("case2 dbg_h_i_o",      dbg_h_i_o,        5'sd1);
        check_u4 ("case2 plus_count",     dbg_plus_count_o, 4'd5);
        check_bit("case2 final spin_o",   spin_o,           1'b1);
        check_bit("case2 flip_o",         flip_o,           1'b1);
        check_bit("case2 bias_accept",    dut.accept_bias_w, 1'b1);
        check_u4 ("case2 bias_rand4",     dut.bias_rand4_w,
                  {dut.rnd32_w[8], dut.rnd32_w[6],
                   dut.rnd32_w[4], dut.rnd32_w[2]});

        // ============================================================
        // Case 3:
        // Bias only, bias_sign = 1.
        // bias contributes +1, so h_i = -(+1) = -1.
        // i0_level=15 makes p_up(-1)=0000, so all five votes are 0.
        // ============================================================

        $display("");
        $display("CASE 3: bias only, bias_sign=1, h_i=-1");

        apply_reset();
        load_seed(32'h1234_5678);

        i0_level_i   = 4'd15;
        clamp_en_i   = 1'b0;
        clamp_spin_i = 1'b0;
        bias_sign_i  = 1'b1;
        bias_prob4_i = 4'hF;

        set_all_valid(1'b0);
        set_all_signs(1'b1);
        set_all_neighbors(1'b1);
        set_all_probs(4'h0);

        init_spin(1'b1);
        start_update_and_wait_done();

        check_s5 ("case3 dbg_h_i_o",      dbg_h_i_o,        -5'sd1);
        check_u4 ("case3 plus_count",     dbg_plus_count_o, 4'd0);
        check_bit("case3 final spin_o",   spin_o,           1'b0);
        check_bit("case3 flip_o",         flip_o,           1'b1);
        check_bit("case3 bias_accept",    dut.accept_bias_w, 1'b1);
        check_u4 ("case3 bias_rand4",     dut.bias_rand4_w,
                  {dut.rnd32_w[8], dut.rnd32_w[6],
                   dut.rnd32_w[4], dut.rnd32_w[2]});

        // ============================================================
        // Case 4:
        // All edges valid, prob = F, sign = +1, neighbor spin = +1.
        // prob4=F is forced accept, so all 8 edges contribute +1.
        // h_sum = +8, h_i = -8.
        // At i0_level=0, p_up should be very small.
        // ============================================================

        $display("");
        $display("CASE 4: all edges always accepted, J=+1, neighbor=+1, h_i=-8");

        apply_reset();
        load_seed(32'h1234_5678);

        i0_level_i = 4'd0;
        clamp_en_i = 1'b0;
        clamp_spin_i = 1'b0;

        set_all_valid(1'b1);
        set_all_signs(1'b1);
        set_all_neighbors(1'b1);
        set_all_probs(4'hF);

        init_spin(1'b1);
        start_update_and_wait_done();

        check_s5 ("case4 dbg_h_i_o",      dbg_h_i_o,        -5'sd8);
        check_u4 ("case4 plus_count",     dbg_plus_count_o, 4'd0);
        check_bit("case4 final spin_o",   spin_o,           1'b0);
        check_bit("case4 flip_o",         flip_o,           1'b1);
        check_u8 ("case4 edge_accept",    dbg_edge_accept_o, 8'hFF);

        // ============================================================
        // Case 5:
        // All edges valid, prob = F, sign = -1, neighbor spin = +1.
        // h_sum = -8, h_i = +8.
        // ============================================================

        $display("");
        $display("CASE 5: all edges always accepted, J=-1, neighbor=+1, h_i=+8");

        apply_reset();
        load_seed(32'h1234_5678);

        i0_level_i = 4'd0;
        clamp_en_i = 1'b0;
        clamp_spin_i = 1'b0;

        set_all_valid(1'b1);
        set_all_signs(1'b0);
        set_all_neighbors(1'b1);
        set_all_probs(4'hF);

        init_spin(1'b0);
        start_update_and_wait_done();

        check_s5 ("case5 dbg_h_i_o",      dbg_h_i_o,        5'sd8);
        check_u4 ("case5 plus_count",     dbg_plus_count_o, 4'd5);
        check_bit("case5 final spin_o",   spin_o,           1'b1);
        check_bit("case5 flip_o",         flip_o,           1'b1);
        check_u8 ("case5 edge_accept",    dbg_edge_accept_o, 8'hFF);

        // ============================================================
        // Case 6:
        // Clamp test.
        // Clamp should bypass random update and force spin to 0 or 1.
        // ============================================================

        $display("");
        $display("CASE 6: clamp function");

        apply_reset();
        load_seed(32'h1234_5678);

        i0_level_i = 4'd0;

        set_all_valid(1'b1);
        set_all_signs(1'b1);
        set_all_neighbors(1'b1);
        set_all_probs(4'hF);

        // First initialize spin to 0.
        init_spin(1'b0);

        // Clamp to 1.
        clamp_en_i   = 1'b1;
        clamp_spin_i = 1'b1;
        start_update_and_wait_done();

        check_bit("case6 clamp to 1 spin_o", spin_o, 1'b1);
        check_bit("case6 clamp to 1 done_o", done_o, 1'b1);

        // Clamp to 0.
        clamp_spin_i = 1'b0;
        start_update_and_wait_done();

        check_bit("case6 clamp to 0 spin_o", spin_o, 1'b0);
        check_bit("case6 clamp to 0 done_o", done_o, 1'b1);

        clamp_en_i   = 1'b0;
        clamp_spin_i = 1'b0;

        // ============================================================
        // Final result
        // ============================================================

        $display("");
        $display("=================================================");
        if (error_count == 0) begin
            $display("tb_pbit_update_core_named PASS");
        end else begin
            $display("tb_pbit_update_core_named FAIL, error_count = %0d", error_count);
        end
        $display("=================================================");

        $finish;
    end

endmodule
