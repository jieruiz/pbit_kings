`timescale 1ns / 1ps

module tb_pbit_array_kings_3x3;

    localparam int ROWS = 3;
    localparam int COLS = 3;
    localparam int N_TRIAL = 5;

    localparam [1:0] EDGE_H   = 2'd0;
    localparam [1:0] EDGE_V   = 2'd1;
    localparam [1:0] EDGE_DSE = 2'd2;
    localparam [1:0] EDGE_DSW = 2'd3;

    logic clk;
    logic rst_n;

    logic phase_start_c0_i;
    logic phase_start_c1_i;
    logic phase_start_c2_i;
    logic phase_start_c3_i;

    logic [3:0] i0_level_i;

    logic        cfg_node_we_i;
    logic [4:0]  cfg_node_row_i;
    logic [4:0]  cfg_node_col_i;
    logic [31:0] cfg_node_seed_i;
    logic        cfg_node_init_spin_i;
    logic        cfg_node_clamp_en_i;
    logic        cfg_node_clamp_spin_i;
    logic        cfg_node_bias_sign_i;
    logic [3:0]  cfg_node_bias_prob4_i;

    logic       cfg_edge_we_i;
    logic [1:0] cfg_edge_type_i;
    logic [4:0] cfg_edge_row_i;
    logic [4:0] cfg_edge_col_i;
    logic [3:0] cfg_edge_prob4_i;
    logic       cfg_edge_sign_i;
    logic       cfg_edge_valid_i;

    wire all_done_c0_o;
    wire all_done_c1_o;
    wire all_done_c2_o;
    wire all_done_c3_o;

    wire [ROWS*COLS-1:0] spin_flat_o;

    integer error_count;
    integer r;
    integer c;

    pbit_array_kings #(
        .ROWS(ROWS),
        .COLS(COLS),
        .N_TRIAL(N_TRIAL)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .phase_start_c0_i       (phase_start_c0_i),
        .phase_start_c1_i       (phase_start_c1_i),
        .phase_start_c2_i       (phase_start_c2_i),
        .phase_start_c3_i       (phase_start_c3_i),

        .i0_level_i             (i0_level_i),

        .cfg_node_we_i          (cfg_node_we_i),
        .cfg_node_row_i         (cfg_node_row_i),
        .cfg_node_col_i         (cfg_node_col_i),
        .cfg_node_seed_i        (cfg_node_seed_i),
        .cfg_node_init_spin_i   (cfg_node_init_spin_i),
        .cfg_node_clamp_en_i    (cfg_node_clamp_en_i),
        .cfg_node_clamp_spin_i  (cfg_node_clamp_spin_i),
        .cfg_node_bias_sign_i   (cfg_node_bias_sign_i),
        .cfg_node_bias_prob4_i  (cfg_node_bias_prob4_i),

        .cfg_edge_we_i          (cfg_edge_we_i),
        .cfg_edge_type_i        (cfg_edge_type_i),
        .cfg_edge_row_i         (cfg_edge_row_i),
        .cfg_edge_col_i         (cfg_edge_col_i),
        .cfg_edge_prob4_i       (cfg_edge_prob4_i),
        .cfg_edge_sign_i        (cfg_edge_sign_i),
        .cfg_edge_valid_i       (cfg_edge_valid_i),

        .all_done_c0_o          (all_done_c0_o),
        .all_done_c1_o          (all_done_c1_o),
        .all_done_c2_o          (all_done_c2_o),
        .all_done_c3_o          (all_done_c3_o),

        .spin_flat_o            (spin_flat_o)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function automatic int idx(input int row, input int col);
        begin
            idx = row * COLS + col;
        end
    endfunction

    task automatic clear_inputs;
        begin
            phase_start_c0_i = 1'b0;
            phase_start_c1_i = 1'b0;
            phase_start_c2_i = 1'b0;
            phase_start_c3_i = 1'b0;

            i0_level_i = 4'd15;

            cfg_node_we_i         = 1'b0;
            cfg_node_row_i        = 5'd0;
            cfg_node_col_i        = 5'd0;
            cfg_node_seed_i       = 32'd0;
            cfg_node_init_spin_i  = 1'b0;
            cfg_node_clamp_en_i   = 1'b0;
            cfg_node_clamp_spin_i = 1'b0;
            cfg_node_bias_sign_i  = 1'b1;
            cfg_node_bias_prob4_i = 4'd0;

            cfg_edge_we_i     = 1'b0;
            cfg_edge_type_i   = 2'd0;
            cfg_edge_row_i    = 5'd0;
            cfg_edge_col_i    = 5'd0;
            cfg_edge_prob4_i  = 4'd0;
            cfg_edge_sign_i   = 1'b1;
            cfg_edge_valid_i  = 1'b0;
        end
    endtask

    task automatic cfg_write_node;
        input [4:0]  row;
        input [4:0]  col;
        input [31:0] seed;
        input        init_spin;
        input        clamp_en;
        input        clamp_spin;
        begin
            @(negedge clk);

            cfg_node_row_i        = row;
            cfg_node_col_i        = col;
            cfg_node_seed_i       = seed;
            cfg_node_init_spin_i  = init_spin;
            cfg_node_clamp_en_i   = clamp_en;
            cfg_node_clamp_spin_i = clamp_spin;
            cfg_node_bias_sign_i  = 1'b1;
            cfg_node_bias_prob4_i = 4'd0;
            cfg_node_we_i         = 1'b1;

            @(negedge clk);

            cfg_node_we_i         = 1'b0;
            cfg_node_row_i        = 5'd0;
            cfg_node_col_i        = 5'd0;
            cfg_node_seed_i       = 32'd0;
            cfg_node_init_spin_i  = 1'b0;
            cfg_node_clamp_en_i   = 1'b0;
            cfg_node_clamp_spin_i = 1'b0;
            cfg_node_bias_sign_i  = 1'b1;
            cfg_node_bias_prob4_i = 4'd0;
        end
    endtask

    task automatic cfg_write_edge;
        input [1:0] edge_type;
        input [4:0] row;
        input [4:0] col;
        input [3:0] prob4;
        input       sign;
        input       valid;
        begin
            @(negedge clk);

            cfg_edge_type_i  = edge_type;
            cfg_edge_row_i   = row;
            cfg_edge_col_i   = col;
            cfg_edge_prob4_i = prob4;
            cfg_edge_sign_i  = sign;
            cfg_edge_valid_i = valid;
            cfg_edge_we_i    = 1'b1;

            @(negedge clk);

            cfg_edge_we_i    = 1'b0;
            cfg_edge_type_i  = 2'd0;
            cfg_edge_row_i   = 5'd0;
            cfg_edge_col_i   = 5'd0;
            cfg_edge_prob4_i = 4'd0;
            cfg_edge_sign_i  = 1'b1;
            cfg_edge_valid_i = 1'b0;
        end
    endtask

    task automatic start_color_and_wait;
        input int color;
        integer timeout;
        begin
            @(negedge clk);

            phase_start_c0_i = (color == 0);
            phase_start_c1_i = (color == 1);
            phase_start_c2_i = (color == 2);
            phase_start_c3_i = (color == 3);

            @(negedge clk);

            phase_start_c0_i = 1'b0;
            phase_start_c1_i = 1'b0;
            phase_start_c2_i = 1'b0;
            phase_start_c3_i = 1'b0;

            timeout = 0;

            while (
                ((color == 0) && !all_done_c0_o) ||
                ((color == 1) && !all_done_c1_o) ||
                ((color == 2) && !all_done_c2_o) ||
                ((color == 3) && !all_done_c3_o)
            ) begin
                @(negedge clk);
                timeout = timeout + 1;

                if (timeout > 200) begin
                    $display("ERROR: timeout waiting for color %0d done", color);
                    error_count = error_count + 1;
                    disable start_color_and_wait;
                end
            end

            $display("PASS: color %0d done after %0d cycles", color, timeout);
        end
    endtask

    task automatic check_spin;
        input int row;
        input int col;
        input expected;
        begin
            if (spin_flat_o[idx(row, col)] !== expected) begin
                $display(
                    "ERROR: spin(%0d,%0d) expected=%b got=%b",
                    row, col, expected, spin_flat_o[idx(row, col)]
                );
                error_count = error_count + 1;
            end else begin
                $display(
                    "PASS : spin(%0d,%0d) = %b",
                    row, col, spin_flat_o[idx(row, col)]
                );
            end
        end
    endtask

    task automatic configure_all_nodes;
        reg init_spin;
        reg clamp_en;
        reg clamp_spin;
        begin
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin

                    // Center node (1,1) is the only free node.
                    // All others are clamped to +1.
                    if ((r == 1) && (c == 1)) begin
                        init_spin  = 1'b0;  // center starts at -1 / 0
                        clamp_en   = 1'b0;
                        clamp_spin = 1'b0;
                    end else begin
                        init_spin  = 1'b1;
                        clamp_en   = 1'b1;
                        clamp_spin = 1'b1;
                    end

                    cfg_write_node(
                        r[4:0],
                        c[4:0],
                        32'h1234_5600 + idx(r, c),
                        init_spin,
                        clamp_en,
                        clamp_spin
                    );

                end
            end
        end
    endtask

    task automatic configure_all_edges;
        begin
            // All edges: prob4=F, sign=0 => J=-1, valid=1.
            // For center node, all eight +1 neighbors produce h_sum=-8, h_i=+8.
            // With i0_level=15, p_up should saturate to +1.

            // Horizontal edges
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS-1; c = c + 1) begin
                    cfg_write_edge(EDGE_H, r[4:0], c[4:0], 4'hF, 1'b0, 1'b1);
                end
            end

            // Vertical edges
            for (r = 0; r < ROWS-1; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin
                    cfg_write_edge(EDGE_V, r[4:0], c[4:0], 4'hF, 1'b0, 1'b1);
                end
            end

            // DSE edges: (r,c) -- (r+1,c+1)
            for (r = 0; r < ROWS-1; r = r + 1) begin
                for (c = 0; c < COLS-1; c = c + 1) begin
                    cfg_write_edge(EDGE_DSE, r[4:0], c[4:0], 4'hF, 1'b0, 1'b1);
                end
            end

            // DSW edges: (r,c) -- (r+1,c-1), c starts at 1
            for (r = 0; r < ROWS-1; r = r + 1) begin
                for (c = 1; c < COLS; c = c + 1) begin
                    cfg_write_edge(EDGE_DSW, r[4:0], c[4:0], 4'hF, 1'b0, 1'b1);
                end
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        error_count = 0;

        $display("=================================================");
        $display("Start tb_pbit_array_kings_3x3");
        $display("=================================================");

        clear_inputs();

        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // High annealing level. h_i=+8 should force p-bit to +1.
        i0_level_i = 4'd15;

        $display("");
        $display("CONFIG: write nodes");
        configure_all_nodes();

        $display("");
        $display("CONFIG: write edges");
        configure_all_edges();

        $display("");
        $display("CHECK initial spins");
        check_spin(1, 1, 1'b0);  // center is free and starts at 0
        check_spin(0, 0, 1'b1);
        check_spin(0, 1, 1'b1);
        check_spin(0, 2, 1'b1);
        check_spin(1, 0, 1'b1);
        check_spin(1, 2, 1'b1);
        check_spin(2, 0, 1'b1);
        check_spin(2, 1, 1'b1);
        check_spin(2, 2, 1'b1);

        // Colors in 3x3:
        // c0: (0,0), (0,2), (2,0), (2,2)
        // c1: (0,1), (2,1)
        // c2: (1,0), (1,2)
        // c3: (1,1)
        //
        // Center is color3, so c0/c1/c2 phases should not update it.

        $display("");
        $display("RUN color 0");
        start_color_and_wait(0);
        check_spin(1, 1, 1'b0);

        $display("");
        $display("RUN color 1");
        start_color_and_wait(1);
        check_spin(1, 1, 1'b0);

        $display("");
        $display("RUN color 2");
        start_color_and_wait(2);
        check_spin(1, 1, 1'b0);

        $display("");
        $display("RUN color 3, center should update to 1");
        start_color_and_wait(3);
        check_spin(1, 1, 1'b1);

        $display("");
        $display("Final spin_flat_o = %b", spin_flat_o);

        $display("");
        $display("=================================================");
        if (error_count == 0) begin
            $display("tb_pbit_array_kings_3x3 PASS");
        end else begin
            $display("tb_pbit_array_kings_3x3 FAIL, error_count=%0d", error_count);
        end
        $display("=================================================");

        $finish;
    end

endmodule
