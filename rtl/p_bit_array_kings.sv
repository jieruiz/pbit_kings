`timescale 1ns / 1ps

module pbit_array_kings #(
    parameter integer ROWS = 19,
    parameter integer COLS = 19,
    parameter integer N_TRIAL = 5
)(
    input  wire clk,
    input  wire rst_n,

    // ------------------------------------------------------------
    // Four phase-start enables.
    // Single clock, four phase enables, not four clocks.
    // ------------------------------------------------------------
    input  wire phase_start_c0_i,
    input  wire phase_start_c1_i,
    input  wire phase_start_c2_i,
    input  wire phase_start_c3_i,

    input  wire [3:0] i0_level_i,

    // ------------------------------------------------------------
    // Node configuration.
    // One node write per cycle.
    // ------------------------------------------------------------
    input  wire        cfg_node_we_i,
    input  wire [4:0]  cfg_node_row_i,
    input  wire [4:0]  cfg_node_col_i,
    input  wire [31:0] cfg_node_seed_i,
    input  wire        cfg_node_init_spin_i,
    input  wire        cfg_node_clamp_en_i,
    input  wire        cfg_node_clamp_spin_i,
    input  wire        cfg_node_bias_sign_i,
    input  wire [3:0]  cfg_node_bias_prob4_i,

    // ------------------------------------------------------------
    // Edge configuration.
    // One edge write per cycle.
    //
    // edge_type:
    // 0 = H   : (r,c) -- (r,c+1)
    // 1 = V   : (r,c) -- (r+1,c)
    // 2 = DSE : (r,c) -- (r+1,c+1)
    // 3 = DSW : (r,c) -- (r+1,c-1)
    // ------------------------------------------------------------
    input  wire        cfg_edge_we_i,
    input  wire [1:0]  cfg_edge_type_i,
    input  wire [4:0]  cfg_edge_row_i,
    input  wire [4:0]  cfg_edge_col_i,
    input  wire [3:0]  cfg_edge_prob4_i,
    input  wire        cfg_edge_sign_i,
    input  wire        cfg_edge_valid_i,

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    output wire all_done_c0_o,
    output wire all_done_c1_o,
    output wire all_done_c2_o,
    output wire all_done_c3_o,

    // Flattened spin readout, bit index = row*COLS + col
    output wire [ROWS*COLS-1:0] spin_flat_o
);

    localparam [1:0] EDGE_H   = 2'd0;
    localparam [1:0] EDGE_V   = 2'd1;
    localparam [1:0] EDGE_DSE = 2'd2;
    localparam [1:0] EDGE_DSW = 2'd3;

    genvar r;
    genvar c;

    // ------------------------------------------------------------
    // Node spin and done arrays
    // ------------------------------------------------------------
    wire spin      [0:ROWS-1][0:COLS-1];
    wire done_hold [0:ROWS-1][0:COLS-1];

    // ------------------------------------------------------------
    // Directional wires into each p-bit
    // ------------------------------------------------------------
    wire [3:0] prob_n  [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_ne [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_e  [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_se [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_s  [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_sw [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_w  [0:ROWS-1][0:COLS-1];
    wire [3:0] prob_nw [0:ROWS-1][0:COLS-1];

    wire valid_n  [0:ROWS-1][0:COLS-1];
    wire valid_ne [0:ROWS-1][0:COLS-1];
    wire valid_e  [0:ROWS-1][0:COLS-1];
    wire valid_se [0:ROWS-1][0:COLS-1];
    wire valid_s  [0:ROWS-1][0:COLS-1];
    wire valid_sw [0:ROWS-1][0:COLS-1];
    wire valid_w  [0:ROWS-1][0:COLS-1];
    wire valid_nw [0:ROWS-1][0:COLS-1];

    wire sign_n  [0:ROWS-1][0:COLS-1];
    wire sign_ne [0:ROWS-1][0:COLS-1];
    wire sign_e  [0:ROWS-1][0:COLS-1];
    wire sign_se [0:ROWS-1][0:COLS-1];
    wire sign_s  [0:ROWS-1][0:COLS-1];
    wire sign_sw [0:ROWS-1][0:COLS-1];
    wire sign_w  [0:ROWS-1][0:COLS-1];
    wire sign_nw [0:ROWS-1][0:COLS-1];

    wire nbr_n  [0:ROWS-1][0:COLS-1];
    wire nbr_ne [0:ROWS-1][0:COLS-1];
    wire nbr_e  [0:ROWS-1][0:COLS-1];
    wire nbr_se [0:ROWS-1][0:COLS-1];
    wire nbr_s  [0:ROWS-1][0:COLS-1];
    wire nbr_sw [0:ROWS-1][0:COLS-1];
    wire nbr_w  [0:ROWS-1][0:COLS-1];
    wire nbr_nw [0:ROWS-1][0:COLS-1];

    // ------------------------------------------------------------
    // Boundary defaults.
    // These directions have no edge coupler driving them.
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_BOUND_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_BOUND_C

                if (r == 0) begin
                    assign prob_n[r][c]  = 4'd0;
                    assign sign_n[r][c]  = 1'b1;
                    assign valid_n[r][c] = 1'b0;
                    assign nbr_n[r][c]   = 1'b0;
                end

                if (r == ROWS-1) begin
                    assign prob_s[r][c]  = 4'd0;
                    assign sign_s[r][c]  = 1'b1;
                    assign valid_s[r][c] = 1'b0;
                    assign nbr_s[r][c]   = 1'b0;
                end

                if (c == 0) begin
                    assign prob_w[r][c]  = 4'd0;
                    assign sign_w[r][c]  = 1'b1;
                    assign valid_w[r][c] = 1'b0;
                    assign nbr_w[r][c]   = 1'b0;
                end

                if (c == COLS-1) begin
                    assign prob_e[r][c]  = 4'd0;
                    assign sign_e[r][c]  = 1'b1;
                    assign valid_e[r][c] = 1'b0;
                    assign nbr_e[r][c]   = 1'b0;
                end

                if ((r == 0) || (c == COLS-1)) begin
                    assign prob_ne[r][c]  = 4'd0;
                    assign sign_ne[r][c]  = 1'b1;
                    assign valid_ne[r][c] = 1'b0;
                    assign nbr_ne[r][c]   = 1'b0;
                end

                if ((r == 0) || (c == 0)) begin
                    assign prob_nw[r][c]  = 4'd0;
                    assign sign_nw[r][c]  = 1'b1;
                    assign valid_nw[r][c] = 1'b0;
                    assign nbr_nw[r][c]   = 1'b0;
                end

                if ((r == ROWS-1) || (c == COLS-1)) begin
                    assign prob_se[r][c]  = 4'd0;
                    assign sign_se[r][c]  = 1'b1;
                    assign valid_se[r][c] = 1'b0;
                    assign nbr_se[r][c]   = 1'b0;
                end

                if ((r == ROWS-1) || (c == 0)) begin
                    assign prob_sw[r][c]  = 4'd0;
                    assign sign_sw[r][c]  = 1'b1;
                    assign valid_sw[r][c] = 1'b0;
                    assign nbr_sw[r][c]   = 1'b0;
                end

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Instantiate all p-bit nodes.
    // Compile-time color:
    // color = 2*(row%2) + (col%2)
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_NODE_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_NODE_C

                localparam integer IDX = r*COLS + c;
                localparam integer CELL_COLOR = (r % 2) * 2 + (c % 2);

                wire local_start_w;
                wire cfg_node_we_match_w;

                assign local_start_w =
                    (CELL_COLOR == 0) ? phase_start_c0_i :
                    (CELL_COLOR == 1) ? phase_start_c1_i :
                    (CELL_COLOR == 2) ? phase_start_c2_i :
                                        phase_start_c3_i;

                assign cfg_node_we_match_w =
                    cfg_node_we_i &&
                    (cfg_node_row_i == r[4:0]) &&
                    (cfg_node_col_i == c[4:0]);

                pbit_node #(
                    .N_TRIAL(N_TRIAL)
                ) u_pbit_node (
                    .clk                 (clk),
                    .rst_n               (rst_n),

                    .local_start_i       (local_start_w),
                    .i0_level_i          (i0_level_i),

                    .cfg_node_we_i       (cfg_node_we_match_w),
                    .cfg_seed_i          (cfg_node_seed_i),
                    .cfg_init_spin_i     (cfg_node_init_spin_i),
                    .cfg_clamp_en_i      (cfg_node_clamp_en_i),
                    .cfg_clamp_spin_i    (cfg_node_clamp_spin_i),
                    .cfg_bias_sign_i     (cfg_node_bias_sign_i),
                    .cfg_bias_prob4_i    (cfg_node_bias_prob4_i),

                    .neighbor_spin_n_i   (nbr_n[r][c]),
                    .neighbor_spin_ne_i  (nbr_ne[r][c]),
                    .neighbor_spin_e_i   (nbr_e[r][c]),
                    .neighbor_spin_se_i  (nbr_se[r][c]),
                    .neighbor_spin_s_i   (nbr_s[r][c]),
                    .neighbor_spin_sw_i  (nbr_sw[r][c]),
                    .neighbor_spin_w_i   (nbr_w[r][c]),
                    .neighbor_spin_nw_i  (nbr_nw[r][c]),

                    .edge_valid_n_i      (valid_n[r][c]),
                    .edge_valid_ne_i     (valid_ne[r][c]),
                    .edge_valid_e_i      (valid_e[r][c]),
                    .edge_valid_se_i     (valid_se[r][c]),
                    .edge_valid_s_i      (valid_s[r][c]),
                    .edge_valid_sw_i     (valid_sw[r][c]),
                    .edge_valid_w_i      (valid_w[r][c]),
                    .edge_valid_nw_i     (valid_nw[r][c]),

                    .edge_sign_n_i       (sign_n[r][c]),
                    .edge_sign_ne_i      (sign_ne[r][c]),
                    .edge_sign_e_i       (sign_e[r][c]),
                    .edge_sign_se_i      (sign_se[r][c]),
                    .edge_sign_s_i       (sign_s[r][c]),
                    .edge_sign_sw_i      (sign_sw[r][c]),
                    .edge_sign_w_i       (sign_w[r][c]),
                    .edge_sign_nw_i      (sign_nw[r][c]),

                    .edge_prob_n_i       (prob_n[r][c]),
                    .edge_prob_ne_i      (prob_ne[r][c]),
                    .edge_prob_e_i       (prob_e[r][c]),
                    .edge_prob_se_i      (prob_se[r][c]),
                    .edge_prob_s_i       (prob_s[r][c]),
                    .edge_prob_sw_i      (prob_sw[r][c]),
                    .edge_prob_w_i       (prob_w[r][c]),
                    .edge_prob_nw_i      (prob_nw[r][c]),

                    .spin_o              (spin[r][c]),
                    .busy_o              (),
                    .done_pulse_o        (),
                    .done_hold_o         (done_hold[r][c]),
                    .flip_o              ()
                );

                assign spin_flat_o[IDX] = spin[r][c];

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Horizontal edges:
    // A=(r,c), B=(r,c+1)
    // A sees B as E, B sees A as W
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : GEN_H_R
            for (c = 0; c < COLS-1; c = c + 1) begin : GEN_H_C

                wire cfg_we_h_w;

                assign cfg_we_h_w =
                    cfg_edge_we_i &&
                    (cfg_edge_type_i == EDGE_H) &&
                    (cfg_edge_row_i == r[4:0]) &&
                    (cfg_edge_col_i == c[4:0]);

                edge_reg_coupler u_edge_h (
                    .clk                  (clk),
                    .rst_n                (rst_n),

                    .cfg_we_i             (cfg_we_h_w),
                    .cfg_prob4_i          (cfg_edge_prob4_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r][c+1]),

                    .prob4_to_a_o         (prob_e[r][c]),
                    .edge_sign_to_a_o     (sign_e[r][c]),
                    .valid_to_a_o         (valid_e[r][c]),
                    .neighbor_spin_to_a_o (nbr_e[r][c]),

                    .prob4_to_b_o         (prob_w[r][c+1]),
                    .edge_sign_to_b_o     (sign_w[r][c+1]),
                    .valid_to_b_o         (valid_w[r][c+1]),
                    .neighbor_spin_to_b_o (nbr_w[r][c+1])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Vertical edges:
    // A=(r,c), B=(r+1,c)
    // A sees B as S, B sees A as N
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS-1; r = r + 1) begin : GEN_V_R
            for (c = 0; c < COLS; c = c + 1) begin : GEN_V_C

                wire cfg_we_v_w;

                assign cfg_we_v_w =
                    cfg_edge_we_i &&
                    (cfg_edge_type_i == EDGE_V) &&
                    (cfg_edge_row_i == r[4:0]) &&
                    (cfg_edge_col_i == c[4:0]);

                edge_reg_coupler u_edge_v (
                    .clk                  (clk),
                    .rst_n                (rst_n),

                    .cfg_we_i             (cfg_we_v_w),
                    .cfg_prob4_i          (cfg_edge_prob4_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r+1][c]),

                    .prob4_to_a_o         (prob_s[r][c]),
                    .edge_sign_to_a_o     (sign_s[r][c]),
                    .valid_to_a_o         (valid_s[r][c]),
                    .neighbor_spin_to_a_o (nbr_s[r][c]),

                    .prob4_to_b_o         (prob_n[r+1][c]),
                    .edge_sign_to_b_o     (sign_n[r+1][c]),
                    .valid_to_b_o         (valid_n[r+1][c]),
                    .neighbor_spin_to_b_o (nbr_n[r+1][c])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Diagonal SE edges:
    // A=(r,c), B=(r+1,c+1)
    // A sees B as SE, B sees A as NW
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS-1; r = r + 1) begin : GEN_DSE_R
            for (c = 0; c < COLS-1; c = c + 1) begin : GEN_DSE_C

                wire cfg_we_dse_w;

                assign cfg_we_dse_w =
                    cfg_edge_we_i &&
                    (cfg_edge_type_i == EDGE_DSE) &&
                    (cfg_edge_row_i == r[4:0]) &&
                    (cfg_edge_col_i == c[4:0]);

                edge_reg_coupler u_edge_dse (
                    .clk                  (clk),
                    .rst_n                (rst_n),

                    .cfg_we_i             (cfg_we_dse_w),
                    .cfg_prob4_i          (cfg_edge_prob4_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r+1][c+1]),

                    .prob4_to_a_o         (prob_se[r][c]),
                    .edge_sign_to_a_o     (sign_se[r][c]),
                    .valid_to_a_o         (valid_se[r][c]),
                    .neighbor_spin_to_a_o (nbr_se[r][c]),

                    .prob4_to_b_o         (prob_nw[r+1][c+1]),
                    .edge_sign_to_b_o     (sign_nw[r+1][c+1]),
                    .valid_to_b_o         (valid_nw[r+1][c+1]),
                    .neighbor_spin_to_b_o (nbr_nw[r+1][c+1])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Diagonal SW edges:
    // A=(r,c), B=(r+1,c-1), c starts from 1
    // A sees B as SW, B sees A as NE
    // ------------------------------------------------------------
    generate
        for (r = 0; r < ROWS-1; r = r + 1) begin : GEN_DSW_R
            for (c = 1; c < COLS; c = c + 1) begin : GEN_DSW_C

                wire cfg_we_dsw_w;

                assign cfg_we_dsw_w =
                    cfg_edge_we_i &&
                    (cfg_edge_type_i == EDGE_DSW) &&
                    (cfg_edge_row_i == r[4:0]) &&
                    (cfg_edge_col_i == c[4:0]);

                edge_reg_coupler u_edge_dsw (
                    .clk                  (clk),
                    .rst_n                (rst_n),

                    .cfg_we_i             (cfg_we_dsw_w),
                    .cfg_prob4_i          (cfg_edge_prob4_i),
                    .cfg_edge_sign_i      (cfg_edge_sign_i),
                    .cfg_valid_i          (cfg_edge_valid_i),

                    .pbit_a_spin_i        (spin[r][c]),
                    .pbit_b_spin_i        (spin[r+1][c-1]),

                    .prob4_to_a_o         (prob_sw[r][c]),
                    .edge_sign_to_a_o     (sign_sw[r][c]),
                    .valid_to_a_o         (valid_sw[r][c]),
                    .neighbor_spin_to_a_o (nbr_sw[r][c]),

                    .prob4_to_b_o         (prob_ne[r+1][c-1]),
                    .edge_sign_to_b_o     (sign_ne[r+1][c-1]),
                    .valid_to_b_o         (valid_ne[r+1][c-1]),
                    .neighbor_spin_to_b_o (nbr_ne[r+1][c-1])
                );

            end
        end
    endgenerate
        // ------------------------------------------------------------
    // Done reduction per color.
    // color = 2*(row%2) + (col%2)
    // ------------------------------------------------------------
    reg all_done_c0_r;
    reg all_done_c1_r;
    reg all_done_c2_r;
    reg all_done_c3_r;

    integer rr;
    integer cc;

    always @(*) begin
        all_done_c0_r = 1'b1;
        all_done_c1_r = 1'b1;
        all_done_c2_r = 1'b1;
        all_done_c3_r = 1'b1;

        for (rr = 0; rr < ROWS; rr = rr + 1) begin
            for (cc = 0; cc < COLS; cc = cc + 1) begin

                if (((rr % 2) == 0) && ((cc % 2) == 0)) begin
                    if (!done_hold[rr][cc])
                        all_done_c0_r = 1'b0;
                end

                if (((rr % 2) == 0) && ((cc % 2) == 1)) begin
                    if (!done_hold[rr][cc])
                        all_done_c1_r = 1'b0;
                end

                if (((rr % 2) == 1) && ((cc % 2) == 0)) begin
                    if (!done_hold[rr][cc])
                        all_done_c2_r = 1'b0;
                end

                if (((rr % 2) == 1) && ((cc % 2) == 1)) begin
                    if (!done_hold[rr][cc])
                        all_done_c3_r = 1'b0;
                end

            end
        end
    end

    assign all_done_c0_o = all_done_c0_r;
    assign all_done_c1_o = all_done_c1_r;
    assign all_done_c2_o = all_done_c2_r;
    assign all_done_c3_o = all_done_c3_r;

endmodule
