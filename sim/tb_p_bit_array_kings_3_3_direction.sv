`timescale 1ns / 1ps

module tb_pbit_array_kings_3x3_direction;

    localparam int ROWS    = 3;
    localparam int COLS    = 3;
    localparam int N_TRIAL = 5;

    localparam [1:0] EDGE_H   = 2'd0;
    localparam [1:0] EDGE_V   = 2'd1;
    localparam [1:0] EDGE_DSE = 2'd2;
    localparam [1:0] EDGE_DSW = 2'd3;

    localparam int DIR_N  = 0;
    localparam int DIR_NE = 1;
    localparam int DIR_E  = 2;
    localparam int DIR_SE = 3;
    localparam int DIR_S  = 4;
    localparam int DIR_SW = 5;
    localparam int DIR_W  = 6;
    localparam int DIR_NW = 7;

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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic int idx(input int row, input int col);
        begin
            idx = row * COLS + col;
        end
    endfunction

    function automatic [127:0] dir_name(input int dir);
        begin
            case (dir)
                DIR_N:  dir_name = "N";
                DIR_NE: dir_name = "NE";
                DIR_E:  dir_name = "E";
                DIR_SE: dir_name = "SE";
                DIR_S:  dir_name = "S";
                DIR_SW: dir_name = "SW";
                DIR_W:  dir_name = "W";
                DIR_NW: dir_name = "NW";
                default: dir_name = "UNKNOWN";
            endcase
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

    task automatic reset_dut;
        begin
            clear_inputs();

            rst_n = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(negedge clk);

            i0_level_i = 4'd15;
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

    task automatic configure_nodes_center_free;
        reg init_spin;
        reg clamp_en;
        reg clamp_spin;
        begin
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin

                    if ((r == 1) && (c == 1)) begin
                        init_spin  = 1'b0;
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
                        ((r == 1) && (c == 1)) ? 32'h8765_4321 : (32'h1234_5600 + idx(r, c)),
                        init_spin,
                        clamp_en,
                        clamp_spin
                    );

                end
            end
        end
    endtask

    task automatic cfg_center_edge_by_dir;
        input int dir;
        input [3:0] prob4;
        input sign;
        input valid;
        begin
            case (dir)
                DIR_N: begin
                    // Center (1,1) sees (0,1) as N.
                    // V edge: A=(0,1), B=(1,1)
                    cfg_write_edge(EDGE_V, 5'd0, 5'd1, prob4, sign, valid);
                end

                DIR_NE: begin
                    // Center (1,1) sees (0,2) as NE.
                    // DSW edge: A=(0,2), B=(1,1)
                    cfg_write_edge(EDGE_DSW, 5'd0, 5'd2, prob4, sign, valid);
                end

                DIR_E: begin
                    // Center (1,1) sees (1,2) as E.
                    // H edge: A=(1,1), B=(1,2)
                    cfg_write_edge(EDGE_H, 5'd1, 5'd1, prob4, sign, valid);
                end

                DIR_SE: begin
                    // Center (1,1) sees (2,2) as SE.
                    // DSE edge: A=(1,1), B=(2,2)
                    cfg_write_edge(EDGE_DSE, 5'd1, 5'd1, prob4, sign, valid);
                end

                DIR_S: begin
                    // Center (1,1) sees (2,1) as S.
                    // V edge: A=(1,1), B=(2,1)
                    cfg_write_edge(EDGE_V, 5'd1, 5'd1, prob4, sign, valid);
                end

                DIR_SW: begin
                    // Center (1,1) sees (2,0) as SW.
                    // DSW edge: A=(1,1), B=(2,0)
                    cfg_write_edge(EDGE_DSW, 5'd1, 5'd1, prob4, sign, valid);
                end

                DIR_W: begin
                    // Center (1,1) sees (1,0) as W.
                    // H edge: A=(1,0), B=(1,1)
                    cfg_write_edge(EDGE_H, 5'd1, 5'd0, prob4, sign, valid);
                end

                DIR_NW: begin
                    // Center (1,1) sees (0,0) as NW.
                    // DSE edge: A=(0,0), B=(1,1)
                    cfg_write_edge(EDGE_DSE, 5'd0, 5'd0, prob4, sign, valid);
                end

                default: begin
                    $display("ERROR: invalid direction %0d", dir);
                    error_count = error_count + 1;
                end
            endcase
        end
    endtask

    task automatic start_color_and_wait;
        input int color;
        integer timeout;
        reg timeout_hit;
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
            timeout_hit = 1'b0;

            while (
                !timeout_hit &&
                (
                    ((color == 0) && !all_done_c0_o) ||
                    ((color == 1) && !all_done_c1_o) ||
                    ((color == 2) && !all_done_c2_o) ||
                    ((color == 3) && !all_done_c3_o)
                )
            ) begin
                @(negedge clk);
                timeout = timeout + 1;

                if (timeout > 300) begin
                    $display("ERROR: timeout waiting for color %0d done", color);
                    error_count = error_count + 1;
                    timeout_hit = 1'b1;
                end
            end

            if (!timeout_hit) begin
                $display("PASS: color %0d done after %0d cycles", color, timeout);
            end
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

    task automatic run_no_edge_baseline;
        begin
            $display("");
            $display("BASELINE: no edge connected to center");

            reset_dut();
            configure_nodes_center_free();

            check_spin(1, 1, 1'b0);

            start_color_and_wait(3);

            // With center seed 0x87654321 and h_i=0,
            // majority should keep center at 0.
            check_spin(1, 1, 1'b0);
        end
    endtask

    task automatic run_direction_case;
        input int dir;
        begin
            $display("");
            $display("DIRECTION CASE: only center edge %0s enabled", dir_name(dir));

            reset_dut();
            configure_nodes_center_free();

            // Enable exactly one edge connected to center:
            // prob=F forced accept, sign=0 means J=-1.
            // Neighbor spin is clamped to 1.
            // h_sum=-1, h_i=+1, i0_level=15 => center should become 1.
            cfg_center_edge_by_dir(dir, 4'hF, 1'b0, 1'b1);

            check_spin(1, 1, 1'b0);

            start_color_and_wait(3);

            check_spin(1, 1, 1'b1);
        end
    endtask

    task automatic run_direction_sign_case;
        begin
            $display("");
            $display("SIGN CASE: center E edge with J=+1 should drive center to 0");

            reset_dut();
            configure_nodes_center_free();

            // E edge, prob=F, sign=1 means J=+1.
            // Neighbor spin is +1, contribution=+1, h_i=-1.
            // i0_level=15 => p_up≈0, center remains 0.
            cfg_center_edge_by_dir(DIR_E, 4'hF, 1'b1, 1'b1);

            check_spin(1, 1, 1'b0);

            start_color_and_wait(3);

            check_spin(1, 1, 1'b0);
        end
    endtask

    initial begin
        error_count = 0;

        $display("=================================================");
        $display("Start tb_pbit_array_kings_3x3_direction");
        $display("=================================================");

        clear_inputs();
        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        i0_level_i = 4'd15;

        run_no_edge_baseline();

        run_direction_case(DIR_N);
        run_direction_case(DIR_NE);
        run_direction_case(DIR_E);
        run_direction_case(DIR_SE);
        run_direction_case(DIR_S);
        run_direction_case(DIR_SW);
        run_direction_case(DIR_W);
        run_direction_case(DIR_NW);

        run_direction_sign_case();

        $display("");
        $display("=================================================");
        if (error_count == 0) begin
            $display("tb_pbit_array_kings_3x3_direction PASS");
        end else begin
            $display("tb_pbit_array_kings_3x3_direction FAIL, error_count=%0d", error_count);
        end
        $display("=================================================");

        $finish;
    end

endmodule
