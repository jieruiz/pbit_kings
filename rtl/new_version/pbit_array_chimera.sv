`ifndef PBIT_ARRAY_CHIMERA
`define PBIT_ARRAY_CHIMERA
import pbit_pkg::*;
module pbit_array_chimera (
    input  logic clk,
    input  logic rst_n,
    // reg_block checks legality and enforces one outstanding request using CFG_BUSY.
    // Hold request valid/data until handshake; issue no new request until response.
    input  logic cfg_req_valid_i,
    output logic cfg_req_ready_o,
    input  var cfg_array_req_t cfg_req_i,
    output logic cfg_rsp_valid_o,
    output cfg_rsp_t cfg_rsp_o,

    // phase_control owns phase/sweep scheduling. All BANKs execute synchronously.
    input  logic phase_start_i,
    input  logic phase_i,
    input  logic [I0_LEVEL_WIDTH-1:0] i0_level_i,
    input  logic [NUM_MAJORITY_WIDTH-1:0] num_majority_i,
    output logic all_phase_done_o,

    input  logic [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr_i,
    input  logic snapshot_latch_pulse_i,
    input  logic snapshot_valid_clr_i,
    output logic [SNAPSHOT_WIDTH-1:0] snapshot_flat_o,
    output logic snapshot_vld_o
);
    localparam int BANK_ROW_IDX_WIDTH = (BANK_ROWS > 1) ? $clog2(BANK_ROWS) : 1;
    localparam int BANK_COL_IDX_WIDTH = (BANK_COLS > 1) ? $clog2(BANK_COLS) : 1;
    logic [BANK_ROWS-1:0] bank_row_hit_w;
    logic [BANK_COLS-1:0] bank_col_hit_w;
    logic [BANK_ROW_IDX_WIDTH-1:0] rsp_row_q, req_row_w;
    logic [BANK_COL_IDX_WIDTH-1:0] rsp_col_q, req_col_w;
    logic req_accept_w;
    logic bank_req_ready_w [0:BANK_ROWS-1][0:BANK_COLS-1];
    logic bank_rsp_valid_w [0:BANK_ROWS-1][0:BANK_COLS-1];
    cfg_rsp_t bank_rsp_w [0:BANK_ROWS-1][0:BANK_COLS-1];
    logic bank_phase_busy_w [0:BANK_ROWS-1][0:BANK_COLS-1];
    logic bank_phase_done_w [0:BANK_ROWS-1][0:BANK_COLS-1];
    logic [3:0] up_spin_w [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_COLS-1];
    logic [3:0] down_spin_w [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_COLS-1];
    logic [3:0] left_spin_w [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_ROWS-1];
    logic [3:0] right_spin_w [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_ROWS-1];
    logic [EDGE_CFG_PACKED_WIDTH-1:0] down_cfg_w
        [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_COLS-1][0:3];
    logic [EDGE_CFG_PACKED_WIDTH-1:0] right_cfg_w
        [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_ROWS-1][0:3];
    logic [NODE_IN_UNIT-1:0] bank_spin_w
        [0:BANK_ROWS-1][0:BANK_COLS-1][0:BANK_TILE_ROWS-1][0:BANK_TILE_COLS-1];
    logic [CFG_DATA_WIDTH-1:0] rsp_row_data_w [0:BANK_ROWS-1];
    logic [BANK_ROWS-1:0] rsp_row_valid_w;
    logic [SPIN_ADDR_MAX*SNAPSHOT_WIDTH-1:0] spin_flat_w;
    logic [SNAPSHOT_WIDTH-1:0] snapshot_d;
    logic snapshot_valid_d;

    // A fixed representative BANK supplies completion; no hardware done reduction.
    assign all_phase_done_o = bank_phase_done_w[0][0];
    assign req_accept_w = cfg_req_valid_i && cfg_req_ready_o;
    // Only the return address is held here. Request payload is captured by the BANK.
    always @(*) begin
        req_row_w = '0;
        for (int r=0; r<BANK_ROWS; r=r+1)
            req_row_w = req_row_w | (BANK_ROW_IDX_WIDTH'(r) & {BANK_ROW_IDX_WIDTH{bank_row_hit_w[r]}});
    end
    always @(*) begin
        req_col_w = '0;
        for (int c=0; c<BANK_COLS; c=c+1)
            req_col_w = req_col_w | (BANK_COL_IDX_WIDTH'(c) & {BANK_COL_IDX_WIDTH{bank_col_hit_w[c]}});
    end
    always @(*) begin
        cfg_req_ready_o = 1'b0;
        for (int r=0; r<BANK_ROWS; r=r+1)
            for (int c=0; c<BANK_COLS; c=c+1)
                cfg_req_ready_o = cfg_req_ready_o |
                    (bank_row_hit_w[r] && bank_col_hit_w[c] && bank_req_ready_w[r][c]);
    end
    genvar br, bc, k, n, r, c;
    generate
        for (br=0; br<BANK_ROWS; br=br+1) begin : GEN_ROW_HIT
            assign bank_row_hit_w[br] = (cfg_req_i.unit_row >= br*BANK_TILE_ROWS) &&
                                      (cfg_req_i.unit_row < (br+1)*BANK_TILE_ROWS);
        end
        for (bc=0; bc<BANK_COLS; bc=bc+1) begin : GEN_COL_HIT
            assign bank_col_hit_w[bc] = (cfg_req_i.unit_col >= bc*BANK_TILE_COLS) &&
                                      (cfg_req_i.unit_col < (bc+1)*BANK_TILE_COLS);
        end
        for (br=0; br<BANK_ROWS; br=br+1) begin : GEN_BANK_ROW
            // Column selection followed by row selection, no extra response cycle.
            assign rsp_row_data_w[br] = bank_rsp_w[br][rsp_col_q].rdata;
            assign rsp_row_valid_w[br] = bank_rsp_valid_w[br][rsp_col_q];
            for (bc=0; bc<BANK_COLS; bc=bc+1) begin : GEN_BANK_COL
                cfg_bank_req_t bank_req_w;
                logic bank_req_valid_w;
                logic [3:0] up_in_w [0:BANK_TILE_COLS-1], down_in_w [0:BANK_TILE_COLS-1];
                logic [3:0] left_in_w [0:BANK_TILE_ROWS-1], right_in_w [0:BANK_TILE_ROWS-1];
                logic [EDGE_CFG_PACKED_WIDTH-1:0] up_cfg_in_w [0:BANK_TILE_COLS-1][0:3];
                logic [EDGE_CFG_PACKED_WIDTH-1:0] left_cfg_in_w [0:BANK_TILE_ROWS-1][0:3];
                assign bank_req_valid_w = cfg_req_valid_i && bank_row_hit_w[br] && bank_col_hit_w[bc];
                assign bank_req_w.cell_row = BANK_LOCAL_ROW_WIDTH'(cfg_req_i.unit_row - br*BANK_TILE_ROWS);
                assign bank_req_w.cell_col = BANK_LOCAL_COL_WIDTH'(cfg_req_i.unit_col - bc*BANK_TILE_COLS);
                assign bank_req_w.payload = cfg_req_i.payload;
                for (k=0; k<BANK_TILE_COLS; k=k+1) begin : GEN_VERTICAL
                    if (br==0) begin : GEN_TOP
                        assign up_in_w[k] = '0;
                        for (n=0; n<4; n=n+1) begin : GEN_CFG
                            assign up_cfg_in_w[k][n] = '0;
                        end
                    end else begin : GEN_UP_BANK
                        assign up_in_w[k] = down_spin_w[br-1][bc][k];
                        for (n=0; n<4; n=n+1) begin : GEN_CFG
                            assign up_cfg_in_w[k][n] = down_cfg_w[br-1][bc][k][n];
                        end
                    end
                    if (br==BANK_ROWS-1) begin : GEN_BOTTOM
                        assign down_in_w[k] = '0;
                    end else begin : GEN_DOWN_BANK
                        assign down_in_w[k] = up_spin_w[br+1][bc][k];
                    end
                end
                for (k=0; k<BANK_TILE_ROWS; k=k+1) begin : GEN_HORIZONTAL
                    if (bc==0) begin : GEN_LEFT
                        assign left_in_w[k] = '0;
                        for (n=0; n<4; n=n+1) begin : GEN_CFG
                            assign left_cfg_in_w[k][n] = '0;
                        end
                    end else begin : GEN_LEFT_BANK
                        assign left_in_w[k] = right_spin_w[br][bc-1][k];
                        for (n=0; n<4; n=n+1) begin : GEN_CFG
                            assign left_cfg_in_w[k][n] = right_cfg_w[br][bc-1][k][n];
                        end
                    end
                    if (bc==BANK_COLS-1) begin : GEN_RIGHT
                        assign right_in_w[k] = '0;
                    end else begin : GEN_RIGHT_BANK
                        assign right_in_w[k] = left_spin_w[br][bc+1][k];
                    end
                end
                pbit_bank #(.BANK_ROW_IDX(br), .BANK_COL_IDX(bc)) u_pbit_bank (
                    .clk(clk), .rst_n(rst_n),
                    .cfg_req_valid_i(bank_req_valid_w), .cfg_req_ready_o(bank_req_ready_w[br][bc]),
                    .cfg_req_i(bank_req_w), .cfg_rsp_valid_o(bank_rsp_valid_w[br][bc]), .cfg_rsp_o(bank_rsp_w[br][bc]),
                    .phase_start_i(phase_start_i), .phase_i(phase_i), .i0_level_i(i0_level_i),
                    .num_majority_i(num_majority_i), .phase_busy_o(bank_phase_busy_w[br][bc]),
                    .phase_done_o(bank_phase_done_w[br][bc]),
                    .up_spin_i(up_in_w), .down_spin_i(down_in_w), .left_spin_i(left_in_w), .right_spin_i(right_in_w),
                    .up_spin_o(up_spin_w[br][bc]), .down_spin_o(down_spin_w[br][bc]),
                    .left_spin_o(left_spin_w[br][bc]), .right_spin_o(right_spin_w[br][bc]),
                    .up_edge_cfg_i(up_cfg_in_w), .left_edge_cfg_i(left_cfg_in_w),
                    .down_edge_cfg_o(down_cfg_w[br][bc]), .right_edge_cfg_o(right_cfg_w[br][bc]),
                    .spin_o(bank_spin_w[br][bc])
                );
            end
        end
        // Global cell row/column ordering, not BANK-major ordering.
        for (r=0; r<ROWS; r=r+1) begin : GEN_SPIN_ROW
            for (c=0; c<COLS; c=c+1) begin : GEN_SPIN_COL
                assign spin_flat_w[(r*COLS+c)*NODE_IN_UNIT +: NODE_IN_UNIT] =
                    bank_spin_w[r/BANK_TILE_ROWS][c/BANK_TILE_COLS][r%BANK_TILE_ROWS][c%BANK_TILE_COLS];
            end
        end
        if (SPIN_ADDR_MAX*SNAPSHOT_WIDTH > N_SPIN) begin : GEN_SNAPSHOT_PADDING
            assign spin_flat_w[SPIN_ADDR_MAX*SNAPSHOT_WIDTH-1:N_SPIN] = '0;
        end
    endgenerate
    assign cfg_rsp_valid_o = rsp_row_valid_w[rsp_row_q];
    assign cfg_rsp_o.rdata = cfg_rsp_valid_o ? rsp_row_data_w[rsp_row_q] : '0;

    // Capture one page only. A simultaneous node commit is observed on a later capture.
    assign snapshot_d = (snapshot_addr_i < SPIN_ADDR_MAX) ?
        spin_flat_w[snapshot_addr_i*SNAPSHOT_WIDTH +: SNAPSHOT_WIDTH] : '0;
    // New capture wins over a simultaneous status read; clearing keeps data intact.
    assign snapshot_valid_d = snapshot_latch_pulse_i ? 1'b1 :
                              snapshot_valid_clr_i ? 1'b0 : snapshot_vld_o;
    // ------------------------------------------------------------
    // Register instances
    // ------------------------------------------------------------
    dffre #(.WIDTH(BANK_ROW_IDX_WIDTH)) rsp_row_ff (
        .clk(clk), .rst_n(rst_n), .en_i(req_accept_w), .d_i(req_row_w), .q_o(rsp_row_q)
    );

    dffre #(.WIDTH(BANK_COL_IDX_WIDTH)) rsp_col_ff (
        .clk(clk), .rst_n(rst_n), .en_i(req_accept_w), .d_i(req_col_w), .q_o(rsp_col_q)
    );

    dffe #(.WIDTH(SNAPSHOT_WIDTH)) snapshot_ff (
        .clk(clk), .en_i(snapshot_latch_pulse_i), .d_i(snapshot_d), .q_o(snapshot_flat_o)
    );

    dffr #(.WIDTH(1)) snapshot_valid_ff (
        .clk(clk), .rst_n(rst_n),
        .d_i(snapshot_valid_d), .q_o(snapshot_vld_o)
    );
endmodule
`endif
