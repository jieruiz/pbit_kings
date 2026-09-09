`ifndef PBIT_BANK
`define PBIT_BANK
import pbit_pkg::*;
module pbit_bank #(
    parameter int BANK_ROW_IDX = 0,
    parameter int BANK_COL_IDX = 0
)(
    input  logic clk,
    input  logic rst_n,
    // Only legal requests reach this interface. One outstanding array transaction.
    input  logic          cfg_req_valid_i,
    output logic          cfg_req_ready_o,
    input  var cfg_bank_req_t cfg_req_i,
    output logic          cfg_rsp_valid_o,
    output cfg_rsp_t      cfg_rsp_o,

    // One synchronous phase command per BANK. N = num_majority_i + 1.
    input  logic phase_start_i,
    input  logic phase_i,
    input  logic [I0_LEVEL_WIDTH-1:0] i0_level_i,
    input  logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,
    output logic phase_busy_o,
    output logic phase_done_o,

    // Up/down indexed by local column; left/right indexed by local row.
    // Each spin bundle is node0..3 vertically or node4..7 horizontally.
    input  wire [3:0] up_spin_i    [0:BANK_TILE_COLS-1],
    input  wire [3:0] down_spin_i  [0:BANK_TILE_COLS-1],
    input  wire [3:0] left_spin_i  [0:BANK_TILE_ROWS-1],
    input  wire [3:0] right_spin_i [0:BANK_TILE_ROWS-1],
    output logic [3:0] up_spin_o    [0:BANK_TILE_COLS-1],
    output logic [3:0] down_spin_o  [0:BANK_TILE_COLS-1],
    output logic [3:0] left_spin_o  [0:BANK_TILE_ROWS-1],
    output logic [3:0] right_spin_o [0:BANK_TILE_ROWS-1],
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0] up_edge_cfg_i
        [0:BANK_TILE_COLS-1][0:3],
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0] left_edge_cfg_i
        [0:BANK_TILE_ROWS-1][0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0] down_edge_cfg_o
        [0:BANK_TILE_COLS-1][0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0] right_edge_cfg_o
        [0:BANK_TILE_ROWS-1][0:3],
    // Array reorders by global cell row/column, then node0..7, for snapshots.
    output logic [NODE_IN_UNIT-1:0] spin_o [0:BANK_TILE_ROWS-1][0:BANK_TILE_COLS-1]
);
    localparam int ROW_BASE = BANK_ROW_IDX * BANK_TILE_ROWS;
    localparam int COL_BASE = BANK_COL_IDX * BANK_TILE_COLS;
    localparam int ACTIVE_ROWS = ((ROWS-ROW_BASE) < BANK_TILE_ROWS) ? ROWS-ROW_BASE : BANK_TILE_ROWS;
    localparam int ACTIVE_COLS = ((COLS-COL_BASE) < BANK_TILE_COLS) ? COLS-COL_BASE : BANK_TILE_COLS;

    // Capture phase context on the SAME acceptance edge as the controller count.
    logic phase_accept_w, phase_q;
    logic [I0_LEVEL_WIDTH-1:0] i0_level_q;
    logic [NUM_MAJORITY_WIDTH-1:0] vote_threshold_d, vote_threshold_q;
    logic [LUT_WIDTH-1:0] pos_thr_by_abs_w [1:7];
    logic lfsr_en_w, mac_en_w, spin_sum_en_w, majority_en_w;

    typedef enum logic [1:0] {S_IDLE, S_EXEC, S_RESP} cfg_state_e;
    cfg_state_e cfg_state_q, cfg_state_d;
    cfg_bank_req_t cfg_req_q;
    logic cfg_accept_w, cfg_exec_w, cfg_capture_w;
    logic [BANK_TILE_ROWS-1:0] cell_row_hit_w;
    logic [BANK_TILE_COLS-1:0] cell_col_hit_w;
    logic node_hit_w, seed_hit_w, edge_hit_w;
    logic [CFG_DATA_WIDTH-1:0] row_rdata_w [0:BANK_TILE_ROWS-1];
    logic [CFG_DATA_WIDTH-1:0] cell_rdata_w [0:BANK_TILE_ROWS-1][0:BANK_TILE_COLS-1];
    logic [CFG_DATA_WIDTH-1:0] selected_rdata_w, rsp_data_d;
    logic [EDGE_CFG_PACKED_WIDTH-1:0] down_edge_w [0:BANK_TILE_ROWS-1][0:BANK_TILE_COLS-1][0:3];
    logic [EDGE_CFG_PACKED_WIDTH-1:0] right_edge_w [0:BANK_TILE_ROWS-1][0:BANK_TILE_COLS-1][0:3];

    assign phase_accept_w = phase_start_i && !phase_busy_o;
    // M is the 0..31 configuration code, N=M+1. Preserve the original tie rule:
    // minimum positive count T=floor(M/2)+1+(M[0]&M[1]), range 1..17.
    assign vote_threshold_d =
        {1'b0, num_majority_i[NUM_MAJORITY_WIDTH-1:1]} +
        {{(NUM_MAJORITY_WIDTH-1){1'b0}}, 1'b1} +
        {{(NUM_MAJORITY_WIDTH-1){1'b0}}, (num_majority_i[0] & num_majority_i[1])};
    pbit_control u_pbit_control (
        .clk(clk), .rst_n(rst_n), .phase_start_i(phase_start_i),
        .num_majority_i(num_majority_i),
        .phase_busy_o(phase_busy_o), .phase_done_o(phase_done_o),
        .lfsr_en_o(lfsr_en_w), .mac_en_o(mac_en_w),
        .spin_sum_en_o(spin_sum_en_w), .majority_en_o(majority_en_w)
    );
    // Combinational LUT driven by the held I0 code. h=0 remains local to each cell.
    tanh_threshold_bank u_tanh_threshold_bank (
        .i0_level_i(i0_level_q), .pos_thr_by_abs_o(pos_thr_by_abs_w)
    );

    // C1: capture request. C2: execute. C3: capture response. C4: owner consumes.
    assign cfg_req_ready_o = rst_n && (cfg_state_q == S_IDLE);
    assign cfg_accept_w = cfg_req_valid_i && cfg_req_ready_o;
    assign cfg_exec_w = (cfg_state_q == S_EXEC);
    assign cfg_capture_w = (cfg_state_q == S_RESP);
    always @(*) begin
        cfg_state_d = cfg_state_q;
        case (cfg_state_q)
            S_IDLE: if (cfg_accept_w) cfg_state_d = S_EXEC;
            S_EXEC: cfg_state_d = S_RESP;
            S_RESP: cfg_state_d = S_IDLE;
            default: cfg_state_d = S_IDLE;
        endcase
    end
    assign rsp_data_d = cfg_req_q.payload.readback ? selected_rdata_w : '0;
    assign node_hit_w = (cfg_req_q.payload.target == CFG_TARGET_NODE);
    assign seed_hit_w = (cfg_req_q.payload.target == CFG_TARGET_SEED);
    assign edge_hit_w = (cfg_req_q.payload.target == CFG_TARGET_EDGE);

    genvar r, c, n;
    generate
        for (r = 0; r < BANK_TILE_ROWS; r = r + 1) begin : GEN_ROW_HIT
            assign cell_row_hit_w[r] = (cfg_req_q.cell_row == BANK_LOCAL_ROW_WIDTH'(r));
        end
        for (c = 0; c < BANK_TILE_COLS; c = c + 1) begin : GEN_COL_HIT
            assign cell_col_hit_w[c] = (cfg_req_q.cell_col == BANK_LOCAL_COL_WIDTH'(c));
        end
        for (r = 0; r < BANK_TILE_ROWS; r = r + 1) begin : GEN_ROW
            // Two-stage one-hot read selection: columns within a row, then rows.
            always @(*) begin
                row_rdata_w[r] = '0;
                for (int col = 0; col < BANK_TILE_COLS; col = col + 1)
                    row_rdata_w[r] = row_rdata_w[r] |
                        (cell_rdata_w[r][col] & {CFG_DATA_WIDTH{cell_col_hit_w[col]}});
            end
            for (c = 0; c < BANK_TILE_COLS; c = c + 1) begin : GEN_COL
                localparam int GLOBAL_ROW = ROW_BASE + r;
                localparam int GLOBAL_COL = COL_BASE + c;
                if ((GLOBAL_ROW < ROWS) && (GLOBAL_COL < COLS)) begin : GEN_VALID
                    logic cell_hit_w, node_we_w, seed_we_w, edge_we_w, edge_clr_w;
                    logic active_col_w;
                    logic [NODE_CFG_W-1:0] node_rdata_w;
                    logic [SEED_WIDTH-1:0] seed_rdata_w;
                    logic [EDGE_RDATA_PACKED_WIDTH-1:0] edge_rdata_w;
                    logic [3:0] up_spin_w, down_spin_w, left_spin_w, right_spin_w;
                    logic [EDGE_CFG_PACKED_WIDTH-1:0] up_cfg_w [0:3], left_cfg_w [0:3];
                    assign cell_hit_w = cell_row_hit_w[r] && cell_col_hit_w[c];
                    assign node_we_w = cfg_exec_w && cell_hit_w && node_hit_w && cfg_req_q.payload.apply;
                    assign seed_we_w = cfg_exec_w && cell_hit_w && seed_hit_w && cfg_req_q.payload.apply;
                    assign edge_we_w = cfg_exec_w && cell_hit_w && edge_hit_w && cfg_req_q.payload.apply;
                    assign edge_clr_w = cfg_exec_w && cell_hit_w && edge_hit_w && cfg_req_q.payload.clear;
                    assign active_col_w = phase_q ^ 1'((GLOBAL_ROW + GLOBAL_COL) % 2);
                    assign cell_rdata_w[r][c] =
                        ({{(CFG_DATA_WIDTH-NODE_CFG_W){1'b0}}, node_rdata_w} & {CFG_DATA_WIDTH{node_hit_w}}) |
                        (seed_rdata_w & {CFG_DATA_WIDTH{seed_hit_w}}) |
                        ({{(CFG_DATA_WIDTH-EDGE_RDATA_PACKED_WIDTH){1'b0}}, edge_rdata_w} & {CFG_DATA_WIDTH{edge_hit_w}});

                    if (r == 0) begin : GEN_UP_PORT
                        assign up_spin_w = up_spin_i[c];
                        for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                            assign up_cfg_w[n] = up_edge_cfg_i[c][n];
                        end
                    end else begin : GEN_UP_CELL
                        assign up_spin_w = spin_o[r-1][c][3:0];
                        for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                            assign up_cfg_w[n] = down_edge_w[r-1][c][n];
                        end
                    end
                    if (r == ACTIVE_ROWS-1) begin : GEN_DOWN_PORT
                        assign down_spin_w = down_spin_i[c];
                    end else begin : GEN_DOWN_CELL
                        assign down_spin_w = spin_o[r+1][c][3:0];
                    end
                    if (c == 0) begin : GEN_LEFT_PORT
                        assign left_spin_w = left_spin_i[r];
                        for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                            assign left_cfg_w[n] = left_edge_cfg_i[r][n];
                        end
                    end else begin : GEN_LEFT_CELL
                        assign left_spin_w = spin_o[r][c-1][7:4];
                        for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                            assign left_cfg_w[n] = right_edge_w[r][c-1][n];
                        end
                    end
                    if (c == ACTIVE_COLS-1) begin : GEN_RIGHT_PORT
                        assign right_spin_w = right_spin_i[r];
                    end else begin : GEN_RIGHT_CELL
                        assign right_spin_w = spin_o[r][c+1][7:4];
                    end
                    if ((GLOBAL_ROW == ROWS-1) && (GLOBAL_COL == COLS-1)) begin : GEN_CORNER
                        unit_cell_corner u_cell (
                            .clk(clk), .rst_n(rst_n),
                            .cfg_node_we_i(node_we_w),
                            .cfg_node_row_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH-1:0]),
                            .cfg_node_col_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH]),
                            .cfg_node_i(cfg_req_q.payload.wdata[NODE_CFG_PACKED_WIDTH-1:0]),
                            .node_rdata_o(node_rdata_w),
                            .cfg_seed_we_i(seed_we_w),
                            .cfg_seed_number_i(cfg_req_q.payload.object_idx[SEED_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_seed_i(cfg_req_q.payload.wdata), .seed_rdata_o(seed_rdata_w),
                            .cfg_edge_we_i(edge_we_w), .cfg_edge_clr_i(edge_clr_w),
                            .cfg_edge_type_i(cfg_req_q.payload.object_idx[CFG_OBJECT_WIDTH-1:EDGE_TARGET_NUMBER_WIDTH]),
                            .cfg_edge_number_i(cfg_req_q.payload.object_idx[EDGE_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_edge_i(cfg_req_q.payload.wdata[EDGE_CFG_PACKED_WIDTH-1:0]),
                            .edge_rdata_o(edge_rdata_w),
                            .active_col_i(active_col_w), .lfsr_en_i(lfsr_en_w), .mac_en_i(mac_en_w),
                            .spin_sum_en_i(spin_sum_en_w), .majority_en_i(majority_en_w),
                            .pos_thr_by_abs_i(pos_thr_by_abs_w), .vote_threshold_i(vote_threshold_q),
                            .up_spin_i(up_spin_w), .down_spin_i(down_spin_w),
                            .left_spin_i(left_spin_w), .right_spin_i(right_spin_w), .spin_o(spin_o[r][c]),
                            .up_edge_cfg_i(up_cfg_w), .left_edge_cfg_i(left_cfg_w),
                            .down_edge_cfg_o(down_edge_w[r][c]), .right_edge_cfg_o(right_edge_w[r][c])
                        );
                    end
                    else if (GLOBAL_ROW == ROWS-1) begin : GEN_LAST_ROW
                        unit_cell_last_row u_cell (
                            .clk(clk), .rst_n(rst_n),
                            .cfg_node_we_i(node_we_w),
                            .cfg_node_row_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH-1:0]),
                            .cfg_node_col_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH]),
                            .cfg_node_i(cfg_req_q.payload.wdata[NODE_CFG_PACKED_WIDTH-1:0]),
                            .node_rdata_o(node_rdata_w),
                            .cfg_seed_we_i(seed_we_w),
                            .cfg_seed_number_i(cfg_req_q.payload.object_idx[SEED_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_seed_i(cfg_req_q.payload.wdata), .seed_rdata_o(seed_rdata_w),
                            .cfg_edge_we_i(edge_we_w), .cfg_edge_clr_i(edge_clr_w),
                            .cfg_edge_type_i(cfg_req_q.payload.object_idx[CFG_OBJECT_WIDTH-1:EDGE_TARGET_NUMBER_WIDTH]),
                            .cfg_edge_number_i(cfg_req_q.payload.object_idx[EDGE_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_edge_i(cfg_req_q.payload.wdata[EDGE_CFG_PACKED_WIDTH-1:0]),
                            .edge_rdata_o(edge_rdata_w),
                            .active_col_i(active_col_w), .lfsr_en_i(lfsr_en_w), .mac_en_i(mac_en_w),
                            .spin_sum_en_i(spin_sum_en_w), .majority_en_i(majority_en_w),
                            .pos_thr_by_abs_i(pos_thr_by_abs_w), .vote_threshold_i(vote_threshold_q),
                            .up_spin_i(up_spin_w), .down_spin_i(down_spin_w),
                            .left_spin_i(left_spin_w), .right_spin_i(right_spin_w), .spin_o(spin_o[r][c]),
                            .up_edge_cfg_i(up_cfg_w), .left_edge_cfg_i(left_cfg_w),
                            .down_edge_cfg_o(down_edge_w[r][c]), .right_edge_cfg_o(right_edge_w[r][c])
                        );
                    end
                    else if (GLOBAL_COL == COLS-1) begin : GEN_LAST_COL
                        unit_cell_last_col u_cell (
                            .clk(clk), .rst_n(rst_n),
                            .cfg_node_we_i(node_we_w),
                            .cfg_node_row_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH-1:0]),
                            .cfg_node_col_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH]),
                            .cfg_node_i(cfg_req_q.payload.wdata[NODE_CFG_PACKED_WIDTH-1:0]),
                            .node_rdata_o(node_rdata_w),
                            .cfg_seed_we_i(seed_we_w),
                            .cfg_seed_number_i(cfg_req_q.payload.object_idx[SEED_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_seed_i(cfg_req_q.payload.wdata), .seed_rdata_o(seed_rdata_w),
                            .cfg_edge_we_i(edge_we_w), .cfg_edge_clr_i(edge_clr_w),
                            .cfg_edge_type_i(cfg_req_q.payload.object_idx[CFG_OBJECT_WIDTH-1:EDGE_TARGET_NUMBER_WIDTH]),
                            .cfg_edge_number_i(cfg_req_q.payload.object_idx[EDGE_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_edge_i(cfg_req_q.payload.wdata[EDGE_CFG_PACKED_WIDTH-1:0]),
                            .edge_rdata_o(edge_rdata_w),
                            .active_col_i(active_col_w), .lfsr_en_i(lfsr_en_w), .mac_en_i(mac_en_w),
                            .spin_sum_en_i(spin_sum_en_w), .majority_en_i(majority_en_w),
                            .pos_thr_by_abs_i(pos_thr_by_abs_w), .vote_threshold_i(vote_threshold_q),
                            .up_spin_i(up_spin_w), .down_spin_i(down_spin_w),
                            .left_spin_i(left_spin_w), .right_spin_i(right_spin_w), .spin_o(spin_o[r][c]),
                            .up_edge_cfg_i(up_cfg_w), .left_edge_cfg_i(left_cfg_w),
                            .down_edge_cfg_o(down_edge_w[r][c]), .right_edge_cfg_o(right_edge_w[r][c])
                        );
                    end
                    else begin : GEN_ORDINARY
                        unit_cell u_cell (
                            .clk(clk), .rst_n(rst_n),
                            .cfg_node_we_i(node_we_w),
                            .cfg_node_row_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH-1:0]),
                            .cfg_node_col_i(cfg_req_q.payload.object_idx[NODE_TARGET_ROW_WIDTH]),
                            .cfg_node_i(cfg_req_q.payload.wdata[NODE_CFG_PACKED_WIDTH-1:0]),
                            .node_rdata_o(node_rdata_w),
                            .cfg_seed_we_i(seed_we_w),
                            .cfg_seed_number_i(cfg_req_q.payload.object_idx[SEED_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_seed_i(cfg_req_q.payload.wdata), .seed_rdata_o(seed_rdata_w),
                            .cfg_edge_we_i(edge_we_w), .cfg_edge_clr_i(edge_clr_w),
                            .cfg_edge_type_i(cfg_req_q.payload.object_idx[CFG_OBJECT_WIDTH-1:EDGE_TARGET_NUMBER_WIDTH]),
                            .cfg_edge_number_i(cfg_req_q.payload.object_idx[EDGE_TARGET_NUMBER_WIDTH-1:0]),
                            .cfg_edge_i(cfg_req_q.payload.wdata[EDGE_CFG_PACKED_WIDTH-1:0]),
                            .edge_rdata_o(edge_rdata_w),
                            .active_col_i(active_col_w), .lfsr_en_i(lfsr_en_w), .mac_en_i(mac_en_w),
                            .spin_sum_en_i(spin_sum_en_w), .majority_en_i(majority_en_w),
                            .pos_thr_by_abs_i(pos_thr_by_abs_w), .vote_threshold_i(vote_threshold_q),
                            .up_spin_i(up_spin_w), .down_spin_i(down_spin_w),
                            .left_spin_i(left_spin_w), .right_spin_i(right_spin_w), .spin_o(spin_o[r][c]),
                            .up_edge_cfg_i(up_cfg_w), .left_edge_cfg_i(left_cfg_w),
                            .down_edge_cfg_o(down_edge_w[r][c]), .right_edge_cfg_o(right_edge_w[r][c])
                        );
                    end
                end else begin : GEN_UNUSED
                    assign spin_o[r][c] = '0;
                    assign cell_rdata_w[r][c] = '0;
                    for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                        assign down_edge_w[r][c][n] = '0;
                        assign right_edge_w[r][c][n] = '0;
                    end
                end
            end
        end
        for (c = 0; c < BANK_TILE_COLS; c = c + 1) begin : GEN_VERTICAL_PORT
            assign up_spin_o[c] = spin_o[0][c][3:0];
            assign down_spin_o[c] = spin_o[ACTIVE_ROWS-1][c][3:0];
            for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                assign down_edge_cfg_o[c][n] = down_edge_w[ACTIVE_ROWS-1][c][n];
            end
        end
        for (r = 0; r < BANK_TILE_ROWS; r = r + 1) begin : GEN_HORIZONTAL_PORT
            assign left_spin_o[r] = spin_o[r][0][7:4];
            assign right_spin_o[r] = spin_o[r][ACTIVE_COLS-1][7:4];
            for (n = 0; n < 4; n = n + 1) begin : GEN_CFG
                assign right_edge_cfg_o[r][n] = right_edge_w[r][ACTIVE_COLS-1][n];
            end
        end
    endgenerate
    always @(*) begin
        selected_rdata_w = '0;
        for (int row = 0; row < BANK_TILE_ROWS; row = row + 1)
            selected_rdata_w = selected_rdata_w |
                (row_rdata_w[row] & {CFG_DATA_WIDTH{cell_row_hit_w[row]}});
    end
    // ------------------------------------------------------------
    // Register instances
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cfg_state_q <= S_IDLE;
        else        cfg_state_q <= cfg_state_d;
    end

    dffre #(.WIDTH(1)) phase_ff (
        .clk(clk), .rst_n(rst_n), .en_i(phase_accept_w), .d_i(phase_i), .q_o(phase_q)
    );

    dffre #(.WIDTH(I0_LEVEL_WIDTH)) i0_level_ff (
        .clk(clk), .rst_n(rst_n), .en_i(phase_accept_w), .d_i(i0_level_i), .q_o(i0_level_q)
    );

    dffre #(.WIDTH(NUM_MAJORITY_WIDTH)) vote_threshold_ff (
        .clk(clk), .rst_n(rst_n), .en_i(phase_accept_w),
        .d_i(vote_threshold_d), .q_o(vote_threshold_q)
    );

    // Payload needs no reset: all writes are qualified by the reset state machine.
    dffe #(.WIDTH(CFG_BANK_REQ_WIDTH)) cfg_request_ff (
        .clk(clk), .en_i(cfg_accept_w), .d_i(cfg_req_i), .q_o(cfg_req_q)
    );

    dffr #(.WIDTH(1)) cfg_response_valid_ff (
        .clk(clk), .rst_n(rst_n), .d_i(cfg_capture_w), .q_o(cfg_rsp_valid_o)
    );

    dffre #(.WIDTH(CFG_RSP_WIDTH)) cfg_response_ff (
        .clk(clk), .rst_n(rst_n), .en_i(cfg_capture_w), .d_i(rsp_data_d), .q_o(cfg_rsp_o)
    );
endmodule
`endif
