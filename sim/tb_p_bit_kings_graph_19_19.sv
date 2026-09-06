`timescale 1ns / 1ps

module tb_pbit_array_kings_19x19_cut;

    localparam int ROWS      = 19;
    localparam int COLS      = 19;
    localparam int N_PHYS    = ROWS * COLS;
    localparam int N_LOGICAL = 50;

    localparam int N_TRIAL   = 5;
    localparam int NUM_SWEEPS = 2000;       // 先用 50 验证，后面可改 5000
    localparam int MAX_CHAIN  = 64;
    localparam int MAX_CUT_EDGES = 1225;

    localparam [1:0] EDGE_H   = 2'd0;
    localparam [1:0] EDGE_V   = 2'd1;
    localparam [1:0] EDGE_DSE = 2'd2;
    localparam [1:0] EDGE_DSW = 2'd3;

    string NODE_CFG_FILE  = "C:\\Users\\86134\\Documents\\p-bit_verilog\\pbit_cfg_out\\node_cfg_19x19.txt";
    string EDGE_CFG_FILE  = "C:\\Users\\86134\\Documents\\p-bit_verilog\\pbit_cfg_out\\edge_cfg_19x19.txt";
    string CHAIN_CFG_FILE = "C:\\Users\\86134\\Documents\\p-bit_verilog\\pbit_cfg_out\\chain_cfg_50.txt";
    string CUT_EDGE_FILE  = "C:\\Users\\86134\\Documents\\p-bit_verilog\\pbit_cfg_out\\cut_edges_50.txt";

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

    wire [N_PHYS-1:0] spin_flat_o;

    integer error_count;

    integer chain_len [0:N_LOGICAL-1];
    integer chain_map [0:N_LOGICAL-1][0:MAX_CHAIN-1];

    integer cut_u [0:MAX_CUT_EDGES-1];
    integer cut_v [0:MAX_CUT_EDGES-1];
    integer cut_w [0:MAX_CUT_EDGES-1];
    integer num_cut_edges;

    reg logical_spin [0:N_LOGICAL-1];

    integer best_cut;
    integer current_cut;

    integer sweep;
    integer phase_idx;
    integer color;

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

    function automatic int phys_idx(input int row, input int col);
        begin
            phys_idx = row * COLS + col;
        end
    endfunction

    task automatic clear_inputs;
        begin
            phase_start_c0_i = 1'b0;
            phase_start_c1_i = 1'b0;
            phase_start_c2_i = 1'b0;
            phase_start_c3_i = 1'b0;

            i0_level_i = 4'd0;

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

    task automatic load_node_cfg;
        integer fd;
        integer status;
        integer row;
        integer col;
        reg [31:0] seed;
        integer init_spin;
        integer clamp_en;
        integer clamp_spin;
        integer count;
        begin
            fd = $fopen(NODE_CFG_FILE, "r");

            if (fd == 0) begin
                $display("FATAL: cannot open %s", NODE_CFG_FILE);
                $finish;
            end

            count = 0;

            while (!$feof(fd)) begin
                status = $fscanf(
                    fd,
                    "%d %d %h %d %d %d\n",
                    row,
                    col,
                    seed,
                    init_spin,
                    clamp_en,
                    clamp_spin
                );

                if (status == 6) begin
                    cfg_write_node(
                        row[4:0],
                        col[4:0],
                        seed,
                        init_spin[0],
                        clamp_en[0],
                        clamp_spin[0]
                    );
                    count = count + 1;
                end
            end

            $fclose(fd);
            $display("Loaded %0d node configs from %s", count, NODE_CFG_FILE);
        end
    endtask

    task automatic load_edge_cfg;
        integer fd;
        integer status;
        integer edge_type;
        integer row;
        integer col;
        reg [3:0] prob4;
        integer sign;
        integer valid;
        integer count;
        begin
            fd = $fopen(EDGE_CFG_FILE, "r");

            if (fd == 0) begin
                $display("FATAL: cannot open %s", EDGE_CFG_FILE);
                $finish;
            end

            count = 0;

            while (!$feof(fd)) begin
                status = $fscanf(
                    fd,
                    "%d %d %d %h %d %d\n",
                    edge_type,
                    row,
                    col,
                    prob4,
                    sign,
                    valid
                );

                if (status == 6) begin
                    cfg_write_edge(
                        edge_type[1:0],
                        row[4:0],
                        col[4:0],
                        prob4,
                        sign[0],
                        valid[0]
                    );
                    count = count + 1;
                end
            end

            $fclose(fd);
            $display("Loaded %0d edge configs from %s", count, EDGE_CFG_FILE);
        end
    endtask

    task automatic load_chain_cfg;
        integer fd;
        integer status;
        integer logical_id;
        integer len;
        integer k;
        integer phys;
        integer count;
        begin
            fd = $fopen(CHAIN_CFG_FILE, "r");

            if (fd == 0) begin
                $display("FATAL: cannot open %s", CHAIN_CFG_FILE);
                $finish;
            end

            for (logical_id = 0; logical_id < N_LOGICAL; logical_id = logical_id + 1) begin
                chain_len[logical_id] = 0;
                for (k = 0; k < MAX_CHAIN; k = k + 1) begin
                    chain_map[logical_id][k] = 0;
                end
            end

            count = 0;

            while (!$feof(fd)) begin
                status = $fscanf(fd, "%d %d", logical_id, len);

                if (status == 2) begin
                    chain_len[logical_id] = len;

                    for (k = 0; k < len; k = k + 1) begin
                        status = $fscanf(fd, "%d", phys);
                        chain_map[logical_id][k] = phys;
                    end

                    count = count + 1;
                end
            end

            $fclose(fd);
            $display("Loaded %0d logical chains from %s", count, CHAIN_CFG_FILE);
        end
    endtask

    task automatic load_cut_edges;
        integer fd;
        integer status;
        integer u;
        integer v;
        integer w;
        begin
            fd = $fopen(CUT_EDGE_FILE, "r");

            if (fd == 0) begin
                $display("FATAL: cannot open %s", CUT_EDGE_FILE);
                $finish;
            end

            num_cut_edges = 0;

            while (!$feof(fd)) begin
                status = $fscanf(fd, "%d %d %d\n", u, v, w);

                if (status == 3) begin
                    cut_u[num_cut_edges] = u;
                    cut_v[num_cut_edges] = v;
                    cut_w[num_cut_edges] = w;
                    num_cut_edges = num_cut_edges + 1;

                    if (num_cut_edges >= MAX_CUT_EDGES) begin
                        $display("FATAL: too many cut edges");
                        $finish;
                    end
                end
            end

            $fclose(fd);
            $display("Loaded %0d cut edges from %s", num_cut_edges, CUT_EDGE_FILE);
        end
    endtask

    function automatic [3:0] anneal_level(input integer sweep_idx);
        integer denom;
        integer num;
        begin
            if (NUM_SWEEPS <= 1) begin
                anneal_level = 4'd15;
            end else begin
                denom = NUM_SWEEPS - 1;
                num   = 15 * sweep_idx + (denom / 2);
                anneal_level = num / denom;
            end
        end
    endfunction

    task automatic start_color_and_wait;
        input integer color;
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

                if (timeout > 500) begin
                    $display("ERROR: timeout waiting for color %0d done", color);
                    error_count = error_count + 1;
                    timeout_hit = 1'b1;
                end
            end
        end
    endtask

    task automatic run_one_sweep;
        input integer sweep_idx;
        begin
            i0_level_i = anneal_level(sweep_idx);

            // 先固定 0->1->2->3。
            // 如果要复现 Python 的 block_order，可以后续从 color_order 文件读取。
            start_color_and_wait(0);
            start_color_and_wait(1);
            start_color_and_wait(2);
            start_color_and_wait(3);
        end
    endtask

    task automatic decode_logical_spins;
        integer l;
        integer k;
        integer sum;
        integer pidx;
        begin
            for (l = 0; l < N_LOGICAL; l = l + 1) begin
                sum = 0;

                for (k = 0; k < chain_len[l]; k = k + 1) begin
                    pidx = chain_map[l][k];

                    if (spin_flat_o[pidx])
                        sum = sum + 1;
                    else
                        sum = sum - 1;
                end

                logical_spin[l] = (sum >= 0);
            end
        end
    endtask

    function automatic integer calc_cut_value;
        integer e;
        integer value;
        begin
            value = 0;

            for (e = 0; e < num_cut_edges; e = e + 1) begin
                if (logical_spin[cut_u[e]] !== logical_spin[cut_v[e]]) begin
                    value = value + cut_w[e];
                end
            end

            calc_cut_value = value;
        end
    endfunction

    task automatic print_logical_spins;
        integer l;
        begin
            $write("logical spins = ");
            for (l = 0; l < N_LOGICAL; l = l + 1) begin
                $write("%0d", logical_spin[l]);
            end
            $write("\n");
        end
    endtask

    initial begin
        error_count = 0;
        best_cut = -1;

        clear_inputs();

        $display("=================================================");
        $display("Start tb_pbit_array_kings_19x19_cut");
        $display("=================================================");

        rst_n = 1'b0;
        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(negedge clk);

        $display("");
        $display("LOAD CONFIG FILES");
        load_chain_cfg();
        load_cut_edges();

        $display("");
        $display("CONFIG NODES");
        load_node_cfg();

        $display("");
        $display("CONFIG EDGES");
        load_edge_cfg();

        $display("");
        $display("RUN SWEEPS");

        for (sweep = 0; sweep < NUM_SWEEPS; sweep = sweep + 1) begin
            run_one_sweep(sweep);

            decode_logical_spins();
            current_cut = calc_cut_value();

            if (current_cut > best_cut) begin
                best_cut = current_cut;
            end

            $display(
                "sweep %0d/%0d, i0_level=%0d, cut=%0d, best_cut=%0d",
                sweep + 1,
                NUM_SWEEPS,
                i0_level_i,
                current_cut,
                best_cut
            );
        end

        decode_logical_spins();
        print_logical_spins();

        $display("");
        $display("=================================================");
        if (error_count == 0) begin
            $display("tb_pbit_array_kings_19x19_cut PASS");
            $display("best_cut = %0d", best_cut);
        end else begin
            $display("tb_pbit_array_kings_19x19_cut FAIL, error_count=%0d", error_count);
        end
        $display("=================================================");

        $finish;
    end

endmodule
