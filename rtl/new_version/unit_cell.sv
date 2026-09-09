`ifndef UNIT_CELL
`define UNIT_CELL
import pbit_pkg::*;
module unit_cell (
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // Configuration requests have already selected this unit cell.
    // pbit_reg checks UNIT bounds/run status and converts a zero seed to one.
    // Node index = {column, row}: left 0..3, right 4..7.
    // ------------------------------------------------------------
    input  logic                                    cfg_node_we_i,
    input  logic [NODE_TARGET_ROW_WIDTH-1:0]         cfg_node_row_i,
    input  logic [NODE_TARGET_COL_WIDTH-1:0]         cfg_node_col_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]         cfg_node_i,
    output logic [NODE_CFG_W-1:0]                   node_rdata_o,

    input  logic                                    cfg_seed_we_i,
    input  logic [SEED_TARGET_NUMBER_WIDTH-1:0]      cfg_seed_number_i,
    input  logic [SEED_WIDTH-1:0]                   cfg_seed_i,
    output logic [SEED_WIDTH-1:0]                   seed_rdata_o,

    input  logic                                    cfg_edge_we_i,
    input  logic                                    cfg_edge_clr_i,
    input  logic [EDGE_TYPE_WIDTH-1:0]              cfg_edge_type_i,
    input  logic [EDGE_TARGET_NUMBER_WIDTH-1:0]     cfg_edge_number_i,
    input  logic [EDGE_CFG_PACKED_WIDTH-1:0]        cfg_edge_i,
    output logic [EDGE_RDATA_PACKED_WIDTH-1:0]      edge_rdata_o,

    // ------------------------------------------------------------
    // Shared BANK thresholds and control. No local phase controller.
    // active_col_i: 0 selects nodes 0..3; 1 selects nodes 4..7.
    // Hold the active column and thresholds through the commit edge.
    // MAC data is registered; sample its result on a later clock edge.
    // All BANKs must submit the same global phase synchronously.
    // ------------------------------------------------------------
    input  logic                                    active_col_i,
    input  logic                                    lfsr_en_i,
    input  logic                                    mac_en_i,
    input  logic                                    spin_sum_en_i,
    input  logic                                    majority_en_i,
    input  wire [LUT_WIDTH-1:0]                     pos_thr_by_abs_i [1:7],
    input  logic [NUM_MAJORITY_WIDTH-1:0]           vote_threshold_i,

    // ------------------------------------------------------------
    // Neighbor spins: up/down use nodes 0..3, left/right use nodes 4..7.
    // Packed spin_o bit n is node n (snapshot order 0..7).
    // ------------------------------------------------------------
    input  logic [3:0]                              up_spin_i,
    input  logic [3:0]                              down_spin_i,
    input  logic [3:0]                              left_spin_i,
    input  logic [3:0]                              right_spin_i,
    output logic [NODE_IN_UNIT-1:0]                  spin_o,

    // Each undirected external edge is stored only by its upper/left owner.
    // Packed edge format is {prob, sign, valid}, as defined in pbit_pkg.
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         up_edge_cfg_i [0:3],
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         left_edge_cfg_i [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         down_edge_cfg_o [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         right_edge_cfg_o [0:3]
);
    // Ordinary K4,4 unit cell: four shared rows and six groups of owned edges.
    localparam int CELL_ROW_NUM = 4;
    localparam int OWNED_EDGE_TYPE_NUM = 6;

    logic [CELL_ROW_NUM-1:0] node_row_hit_w;
    logic [1:0]             node_col_hit_w;
    logic [CELL_ROW_NUM-1:0] seed_hit_w;
    logic [CELL_ROW_NUM-1:0] edge_number_hit_w;
    logic [OWNED_EDGE_TYPE_NUM-1:0] edge_type_hit_w;
    logic [1:0]             node_commit_w;
    logic [NODE_CFG_W-1:0] node_rcfg_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] node_bias_sign_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] node_bias_prob_w [0:NODE_IN_UNIT-1];

    // Types 0..3: internal_edge[left_row][right_row]. Type 4: right; type 5: down.
    logic [EDGE_CFG_PACKED_WIDTH-1:0] owned_edge_cfg_w [0:OWNED_EDGE_TYPE_NUM-1][0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_a_w [0:OWNED_EDGE_TYPE_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_b_w [0:OWNED_EDGE_TYPE_NUM-1];

    logic [SEED_WIDTH-1:0] rnd32_w [0:CELL_ROW_NUM-1];
    logic signed [MACSUM_WIDTH-1:0] macsum_w [0:CELL_ROW_NUM-1];
    logic [LUT_WIDTH-1:0] p_up_thr_w [0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] majority_spin_w;

    // ------------------------------------------------------------
    // Shared local address decoders and node storage
    // ------------------------------------------------------------
    genvar row, col, edge_type, number, lane;
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_TARGET_ROW
            assign node_row_hit_w[row] = cfg_node_row_i == NODE_TARGET_ROW_WIDTH'(row);
            assign seed_hit_w[row] = cfg_seed_number_i == SEED_TARGET_NUMBER_WIDTH'(row);
            assign edge_number_hit_w[row] = cfg_edge_number_i == EDGE_TARGET_NUMBER_WIDTH'(row);
        end
        for (col = 0; col < 2; col = col + 1) begin : GEN_NODE_COL
            assign node_col_hit_w[col] = cfg_node_col_i == NODE_TARGET_COL_WIDTH'(col);
            assign node_commit_w[col] = majority_en_i && (active_col_i == 1'(col));
            for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_NODE_ROW
                localparam int NODE_IDX = col * CELL_ROW_NUM + row;
                pbit_node u_pbit_node (
                    .clk                 (clk),
                    .rst_n               (rst_n),
                    .local_cfg_node_we_i (cfg_node_we_i && node_col_hit_w[col] && node_row_hit_w[row]),
                    .local_node_cfg_i    (cfg_node_i),
                    .local_node_rcfg_o   (node_rcfg_w[NODE_IDX]),
                    .bias_sign_o         (node_bias_sign_w[NODE_IDX]),
                    .bias_prob_o         (node_bias_prob_w[NODE_IDX]),
                    .majority_en_i       (node_commit_w[col]),
                    .majority_spin_i     (majority_spin_w[row]),
                    .spin_o              (spin_o[NODE_IDX])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // 24 owned edge registers. Both endpoints see the same stored parameters.
    // ------------------------------------------------------------
    generate
        for (edge_type = 0; edge_type < OWNED_EDGE_TYPE_NUM; edge_type = edge_type + 1) begin : GEN_EDGE_TYPE
            assign edge_type_hit_w[edge_type] = cfg_edge_type_i == EDGE_TYPE_WIDTH'(edge_type);
            for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_EDGE_NUMBER
                logic target_hit_w;
                logic endpoint_a_w, endpoint_b_w;
                assign target_hit_w = edge_type_hit_w[edge_type] && edge_number_hit_w[number];
                if (edge_type < CELL_ROW_NUM) begin : GEN_INTERNAL
                    assign endpoint_a_w = spin_o[edge_type];
                    assign endpoint_b_w = spin_o[CELL_ROW_NUM+number];
                end else if (edge_type == 4) begin : GEN_RIGHT
                    assign endpoint_a_w = spin_o[CELL_ROW_NUM+number];
                    assign endpoint_b_w = right_spin_i[number];
                end else begin : GEN_DOWN
                    assign endpoint_a_w = spin_o[number];
                    assign endpoint_b_w = down_spin_i[number];
                end
                edge_reg_coupler u_edge_reg_coupler (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .cfg_we_i             (cfg_edge_we_i && target_hit_w),
                    .cfg_clr_pulse_i      (cfg_edge_clr_i && target_hit_w),
                    .cfg_prob_i           (cfg_edge_i[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .cfg_edge_sign_i      (cfg_edge_i[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .cfg_valid_i          (cfg_edge_i[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .pbit_a_spin_i        (endpoint_a_w),
                    .pbit_b_spin_i        (endpoint_b_w),
                    .prob_to_a_o          (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .edge_sign_to_a_o     (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .valid_to_a_o         (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .neighbor_spin_to_a_o (edge_neighbor_a_w[edge_type][number]),
                    .prob_to_b_o          (),
                    .edge_sign_to_b_o     (),
                    .valid_to_b_o         (),
                    .neighbor_spin_to_b_o (edge_neighbor_b_w[edge_type][number])
                );
            end
        end
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_EDGE_EXPORT
            assign right_edge_cfg_o[row] = owned_edge_cfg_w[4][row];
            assign down_edge_cfg_o[row] = owned_edge_cfg_w[5][row];
        end
    endgenerate

    // ------------------------------------------------------------
    // Four datapaths, each shared by node row and node row+4.
    // The column mux is before the MAC register, with no added pipeline stage.
    // ------------------------------------------------------------
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_DATAPATH
            logic [EDGE_CFG_PACKED_WIDTH-1:0] selected_edge_w [0:MAC_EDGE_NUM-1];
            logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w [0:MAC_EDGE_NUM-1];
            logic [MAC_EDGE_NUM-1:0] edge_valid_w, edge_sign_w, neighbor_spin_w;
            logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign_w;
            logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_w;

            assign bias_sign_w = active_col_i ? node_bias_sign_w[CELL_ROW_NUM+row] : node_bias_sign_w[row];
            assign bias_prob_w = active_col_i ? node_bias_prob_w[CELL_ROW_NUM+row] : node_bias_prob_w[row];
            for (lane = 0; lane < CELL_ROW_NUM; lane = lane + 1) begin : GEN_INTERNAL_LANE
                // Right-column nodes traverse columns of the same K4,4 edge matrix.
                assign selected_edge_w[lane] = active_col_i ? owned_edge_cfg_w[lane][row] : owned_edge_cfg_w[row][lane];
                assign neighbor_spin_w[lane] = active_col_i ? edge_neighbor_b_w[lane][row] : edge_neighbor_a_w[row][lane];
            end
            // Incoming edges belong to the left/upper neighbor; outgoing edges belong here.
            assign selected_edge_w[4] = active_col_i ? left_edge_cfg_i[row] : up_edge_cfg_i[row];
            assign selected_edge_w[5] = active_col_i ? owned_edge_cfg_w[4][row] : owned_edge_cfg_w[5][row];
            assign neighbor_spin_w[4] = active_col_i ? left_spin_i[row] : up_spin_i[row];
            assign neighbor_spin_w[5] = active_col_i ? edge_neighbor_a_w[4][row] : edge_neighbor_a_w[5][row];
            for (lane = 0; lane < MAC_EDGE_NUM; lane = lane + 1) begin : GEN_EDGE_FIELDS
                assign edge_valid_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB];
                assign edge_sign_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB];
                assign edge_prob_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB];
            end

            lfsr32_rng32 u_lfsr32_rng32 (
                .clk       (clk),
                .rst_n     (rst_n),
                .seed_we_i (cfg_seed_we_i && seed_hit_w[row]),
                .seed_i    (cfg_seed_i),
                .en_i      (lfsr_en_i),
                .rnd32_o   (rnd32_w[row])
            );
            mac u_mac (
                .clk             (clk),
                .rnd32_i         (rnd32_w[row]),
                .bias_sign_i     (bias_sign_w),
                .bias_prob_i     (bias_prob_w),
                .neighbor_spin_i (neighbor_spin_w),
                .edge_valid_i    (edge_valid_w),
                .edge_sign_i     (edge_sign_w),
                .edge_prob_i     (edge_prob_w),
                .macsum_en_i     (mac_en_i),
                .macsum_o        (macsum_w[row])
            );
            tanh_threshold_select u_tanh_threshold_select (
                .h_i              (macsum_w[row]),
                .pos_thr_by_abs_i  (pos_thr_by_abs_i),
                .p_up_thr_o       (p_up_thr_w[row])
            );
            comparator_vote u_comparator_vote (
                .clk              (clk),
                .rst_n            (rst_n),
                .rnd32_i          (rnd32_w[row]),
                .p_up_thr_i       (p_up_thr_w[row]),
                .spin_sum_en_i    (spin_sum_en_i),
                .majority_en_i    (majority_en_i),
                .vote_threshold_i (vote_threshold_i),
                .majority_spin_o  (majority_spin_w[row])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Combinational readback. The bus controller captures after APPLY commits.
    // Types 6/7 do not match a write decoder and return zero here.
    // ------------------------------------------------------------
    assign node_rdata_o = node_rcfg_w[{cfg_node_col_i, cfg_node_row_i}];
    assign seed_rdata_o = rnd32_w[cfg_seed_number_i];
    always @(*) begin
        case (cfg_edge_type_i)
            3'd0: edge_rdata_o = owned_edge_cfg_w[0][cfg_edge_number_i];
            3'd1: edge_rdata_o = owned_edge_cfg_w[1][cfg_edge_number_i];
            3'd2: edge_rdata_o = owned_edge_cfg_w[2][cfg_edge_number_i];
            3'd3: edge_rdata_o = owned_edge_cfg_w[3][cfg_edge_number_i];
            3'd4: edge_rdata_o = owned_edge_cfg_w[4][cfg_edge_number_i];
            3'd5: edge_rdata_o = owned_edge_cfg_w[5][cfg_edge_number_i];
            default: edge_rdata_o = '0;
        endcase
    end
endmodule

// Last array row: 16 internal edges and 4 right edges; no down-edge registers.
module unit_cell_last_row (
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // Configuration requests have already selected this unit cell.
    // pbit_reg checks UNIT bounds/run status and converts a zero seed to one.
    // Node index = {column, row}: left 0..3, right 4..7.
    // ------------------------------------------------------------
    input  logic                                    cfg_node_we_i,
    input  logic [NODE_TARGET_ROW_WIDTH-1:0]         cfg_node_row_i,
    input  logic [NODE_TARGET_COL_WIDTH-1:0]         cfg_node_col_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]         cfg_node_i,
    output logic [NODE_CFG_W-1:0]                   node_rdata_o,

    input  logic                                    cfg_seed_we_i,
    input  logic [SEED_TARGET_NUMBER_WIDTH-1:0]      cfg_seed_number_i,
    input  logic [SEED_WIDTH-1:0]                   cfg_seed_i,
    output logic [SEED_WIDTH-1:0]                   seed_rdata_o,

    input  logic                                    cfg_edge_we_i,
    input  logic                                    cfg_edge_clr_i,
    input  logic [EDGE_TYPE_WIDTH-1:0]              cfg_edge_type_i,
    input  logic [EDGE_TARGET_NUMBER_WIDTH-1:0]     cfg_edge_number_i,
    input  logic [EDGE_CFG_PACKED_WIDTH-1:0]        cfg_edge_i,
    output logic [EDGE_RDATA_PACKED_WIDTH-1:0]      edge_rdata_o,

    // ------------------------------------------------------------
    // Shared BANK thresholds and control. No local phase controller.
    // active_col_i: 0 selects nodes 0..3; 1 selects nodes 4..7.
    // Hold the active column and thresholds through the commit edge.
    // MAC data is registered; sample its result on a later clock edge.
    // All BANKs must submit the same global phase synchronously.
    // ------------------------------------------------------------
    input  logic                                    active_col_i,
    input  logic                                    lfsr_en_i,
    input  logic                                    mac_en_i,
    input  logic                                    spin_sum_en_i,
    input  logic                                    majority_en_i,
    input  wire [LUT_WIDTH-1:0]                     pos_thr_by_abs_i [1:7],
    input  logic [NUM_MAJORITY_WIDTH-1:0]           vote_threshold_i,

    // ------------------------------------------------------------
    // Neighbor spins: up/down use nodes 0..3, left/right use nodes 4..7.
    // Packed spin_o bit n is node n (snapshot order 0..7).
    // ------------------------------------------------------------
    input  logic [3:0]                              up_spin_i,
    input  logic [3:0]                              down_spin_i,
    input  logic [3:0]                              left_spin_i,
    input  logic [3:0]                              right_spin_i,
    output logic [NODE_IN_UNIT-1:0]                  spin_o,

    // Each undirected external edge is stored only by its upper/left owner.
    // Packed edge format is {prob, sign, valid}, as defined in pbit_pkg.
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         up_edge_cfg_i [0:3],
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         left_edge_cfg_i [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         down_edge_cfg_o [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         right_edge_cfg_o [0:3]
);
    // Last array row: 16 internal edges and 4 right edges; no down-edge registers.
    // Keep six edge-type wiring slots; absent slots are constant zero.
    localparam int CELL_ROW_NUM = 4;
    localparam int OWNED_EDGE_TYPE_NUM = 6;

    logic [CELL_ROW_NUM-1:0] node_row_hit_w;
    logic [1:0]             node_col_hit_w;
    logic [CELL_ROW_NUM-1:0] seed_hit_w;
    logic [CELL_ROW_NUM-1:0] edge_number_hit_w;
    logic [OWNED_EDGE_TYPE_NUM-1:0] edge_type_hit_w;
    logic [1:0]             node_commit_w;
    logic [NODE_CFG_W-1:0] node_rcfg_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] node_bias_sign_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] node_bias_prob_w [0:NODE_IN_UNIT-1];

    // Types 0..3: internal_edge[left_row][right_row]. Type 4: right; type 5: down.
    logic [EDGE_CFG_PACKED_WIDTH-1:0] owned_edge_cfg_w [0:OWNED_EDGE_TYPE_NUM-1][0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_a_w [0:OWNED_EDGE_TYPE_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_b_w [0:OWNED_EDGE_TYPE_NUM-1];

    logic [SEED_WIDTH-1:0] rnd32_w [0:CELL_ROW_NUM-1];
    logic signed [MACSUM_WIDTH-1:0] macsum_w [0:CELL_ROW_NUM-1];
    logic [LUT_WIDTH-1:0] p_up_thr_w [0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] majority_spin_w;

    // ------------------------------------------------------------
    // Shared local address decoders and node storage
    // ------------------------------------------------------------
    genvar row, col, edge_type, number, lane;
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_TARGET_ROW
            assign node_row_hit_w[row] = cfg_node_row_i == NODE_TARGET_ROW_WIDTH'(row);
            assign seed_hit_w[row] = cfg_seed_number_i == SEED_TARGET_NUMBER_WIDTH'(row);
            assign edge_number_hit_w[row] = cfg_edge_number_i == EDGE_TARGET_NUMBER_WIDTH'(row);
        end
        for (col = 0; col < 2; col = col + 1) begin : GEN_NODE_COL
            assign node_col_hit_w[col] = cfg_node_col_i == NODE_TARGET_COL_WIDTH'(col);
            assign node_commit_w[col] = majority_en_i && (active_col_i == 1'(col));
            for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_NODE_ROW
                localparam int NODE_IDX = col * CELL_ROW_NUM + row;
                pbit_node u_pbit_node (
                    .clk                 (clk),
                    .rst_n               (rst_n),
                    .local_cfg_node_we_i (cfg_node_we_i && node_col_hit_w[col] && node_row_hit_w[row]),
                    .local_node_cfg_i    (cfg_node_i),
                    .local_node_rcfg_o   (node_rcfg_w[NODE_IDX]),
                    .bias_sign_o         (node_bias_sign_w[NODE_IDX]),
                    .bias_prob_o         (node_bias_prob_w[NODE_IDX]),
                    .majority_en_i       (node_commit_w[col]),
                    .majority_spin_i     (majority_spin_w[row]),
                    .spin_o              (spin_o[NODE_IDX])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // 20 owned edge registers. Both endpoints see the same stored parameters.
    // ------------------------------------------------------------
    generate
        for (edge_type = 0; edge_type < CELL_ROW_NUM; edge_type = edge_type + 1) begin : GEN_EDGE_TYPE
            assign edge_type_hit_w[edge_type] = cfg_edge_type_i == EDGE_TYPE_WIDTH'(edge_type);
            for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_EDGE_NUMBER
                logic target_hit_w;
                logic endpoint_a_w, endpoint_b_w;
                assign target_hit_w = edge_type_hit_w[edge_type] && edge_number_hit_w[number];
                assign endpoint_a_w = spin_o[edge_type];
                assign endpoint_b_w = spin_o[CELL_ROW_NUM+number];
                edge_reg_coupler u_edge_reg_coupler (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .cfg_we_i             (cfg_edge_we_i && target_hit_w),
                    .cfg_clr_pulse_i      (cfg_edge_clr_i && target_hit_w),
                    .cfg_prob_i           (cfg_edge_i[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .cfg_edge_sign_i      (cfg_edge_i[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .cfg_valid_i          (cfg_edge_i[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .pbit_a_spin_i        (endpoint_a_w),
                    .pbit_b_spin_i        (endpoint_b_w),
                    .prob_to_a_o          (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .edge_sign_to_a_o     (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .valid_to_a_o         (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .neighbor_spin_to_a_o (edge_neighbor_a_w[edge_type][number]),
                    .prob_to_b_o          (),
                    .edge_sign_to_b_o     (),
                    .valid_to_b_o         (),
                    .neighbor_spin_to_b_o (edge_neighbor_b_w[edge_type][number])
                );
            end
        end
        assign edge_type_hit_w[4] = cfg_edge_type_i == 3'd4;
        for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_RIGHT_EDGE
            logic target_hit_w;
            logic endpoint_a_w, endpoint_b_w;
            assign target_hit_w = edge_type_hit_w[4] && edge_number_hit_w[number];
            assign endpoint_a_w = spin_o[CELL_ROW_NUM+number];
            assign endpoint_b_w = right_spin_i[number];
            edge_reg_coupler u_edge_reg_coupler (
                .clk                  (clk),
                .rst_n                (rst_n),
                .cfg_we_i             (cfg_edge_we_i && target_hit_w),
                .cfg_clr_pulse_i      (cfg_edge_clr_i && target_hit_w),
                .cfg_prob_i           (cfg_edge_i[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                .cfg_edge_sign_i      (cfg_edge_i[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                .cfg_valid_i          (cfg_edge_i[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                .pbit_a_spin_i        (endpoint_a_w),
                .pbit_b_spin_i        (endpoint_b_w),
                .prob_to_a_o          (owned_edge_cfg_w[4][number][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                .edge_sign_to_a_o     (owned_edge_cfg_w[4][number][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                .valid_to_a_o         (owned_edge_cfg_w[4][number][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                .neighbor_spin_to_a_o (edge_neighbor_a_w[4][number]),
                .prob_to_b_o          (),
                .edge_sign_to_b_o     (),
                .valid_to_b_o         (),
                .neighbor_spin_to_b_o (edge_neighbor_b_w[4][number])
            );
        end
        // Missing down edges are constants, with no storage or write decoder.
        assign edge_type_hit_w[5] = 1'b0;
        assign edge_neighbor_a_w[5] = '0;
        assign edge_neighbor_b_w[5] = '0;
        for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_NO_DOWN_EDGE
            assign owned_edge_cfg_w[5][number] = '0;
        end
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_EDGE_EXPORT
            assign right_edge_cfg_o[row] = owned_edge_cfg_w[4][row];
            assign down_edge_cfg_o[row] = owned_edge_cfg_w[5][row];
        end
    endgenerate

    // ------------------------------------------------------------
    // Four datapaths, each shared by node row and node row+4.
    // The column mux is before the MAC register, with no added pipeline stage.
    // ------------------------------------------------------------
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_DATAPATH
            logic [EDGE_CFG_PACKED_WIDTH-1:0] selected_edge_w [0:MAC_EDGE_NUM-1];
            logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w [0:MAC_EDGE_NUM-1];
            logic [MAC_EDGE_NUM-1:0] edge_valid_w, edge_sign_w, neighbor_spin_w;
            logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign_w;
            logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_w;

            assign bias_sign_w = active_col_i ? node_bias_sign_w[CELL_ROW_NUM+row] : node_bias_sign_w[row];
            assign bias_prob_w = active_col_i ? node_bias_prob_w[CELL_ROW_NUM+row] : node_bias_prob_w[row];
            for (lane = 0; lane < CELL_ROW_NUM; lane = lane + 1) begin : GEN_INTERNAL_LANE
                // Right-column nodes traverse columns of the same K4,4 edge matrix.
                assign selected_edge_w[lane] = active_col_i ? owned_edge_cfg_w[lane][row] : owned_edge_cfg_w[row][lane];
                assign neighbor_spin_w[lane] = active_col_i ? edge_neighbor_b_w[lane][row] : edge_neighbor_a_w[row][lane];
            end
            // Incoming edges belong to the left/upper neighbor; outgoing edges belong here.
            assign selected_edge_w[4] = active_col_i ? left_edge_cfg_i[row] : up_edge_cfg_i[row];
            assign selected_edge_w[5] = active_col_i ? owned_edge_cfg_w[4][row] : owned_edge_cfg_w[5][row];
            assign neighbor_spin_w[4] = active_col_i ? left_spin_i[row] : up_spin_i[row];
            assign neighbor_spin_w[5] = active_col_i ? edge_neighbor_a_w[4][row] : edge_neighbor_a_w[5][row];
            for (lane = 0; lane < MAC_EDGE_NUM; lane = lane + 1) begin : GEN_EDGE_FIELDS
                assign edge_valid_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB];
                assign edge_sign_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB];
                assign edge_prob_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB];
            end

            lfsr32_rng32 u_lfsr32_rng32 (
                .clk       (clk),
                .rst_n     (rst_n),
                .seed_we_i (cfg_seed_we_i && seed_hit_w[row]),
                .seed_i    (cfg_seed_i),
                .en_i      (lfsr_en_i),
                .rnd32_o   (rnd32_w[row])
            );
            mac u_mac (
                .clk             (clk),
                .rnd32_i         (rnd32_w[row]),
                .bias_sign_i     (bias_sign_w),
                .bias_prob_i     (bias_prob_w),
                .neighbor_spin_i (neighbor_spin_w),
                .edge_valid_i    (edge_valid_w),
                .edge_sign_i     (edge_sign_w),
                .edge_prob_i     (edge_prob_w),
                .macsum_en_i     (mac_en_i),
                .macsum_o        (macsum_w[row])
            );
            tanh_threshold_select u_tanh_threshold_select (
                .h_i              (macsum_w[row]),
                .pos_thr_by_abs_i  (pos_thr_by_abs_i),
                .p_up_thr_o       (p_up_thr_w[row])
            );
            comparator_vote u_comparator_vote (
                .clk              (clk),
                .rst_n            (rst_n),
                .rnd32_i          (rnd32_w[row]),
                .p_up_thr_i       (p_up_thr_w[row]),
                .spin_sum_en_i    (spin_sum_en_i),
                .majority_en_i    (majority_en_i),
                .vote_threshold_i (vote_threshold_i),
                .majority_spin_o  (majority_spin_w[row])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Combinational readback. The bus controller captures after APPLY commits.
    // Missing boundary edges and types 6/7 return zero and never accept writes.
    // ------------------------------------------------------------
    assign node_rdata_o = node_rcfg_w[{cfg_node_col_i, cfg_node_row_i}];
    assign seed_rdata_o = rnd32_w[cfg_seed_number_i];
    always @(*) begin
        case (cfg_edge_type_i)
            3'd0: edge_rdata_o = owned_edge_cfg_w[0][cfg_edge_number_i];
            3'd1: edge_rdata_o = owned_edge_cfg_w[1][cfg_edge_number_i];
            3'd2: edge_rdata_o = owned_edge_cfg_w[2][cfg_edge_number_i];
            3'd3: edge_rdata_o = owned_edge_cfg_w[3][cfg_edge_number_i];
            3'd4: edge_rdata_o = owned_edge_cfg_w[4][cfg_edge_number_i];
            3'd5: edge_rdata_o = owned_edge_cfg_w[5][cfg_edge_number_i];
            default: edge_rdata_o = '0;
        endcase
    end
endmodule

// Last array column: 16 internal edges and 4 down edges; no right-edge registers.
module unit_cell_last_col (
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // Configuration requests have already selected this unit cell.
    // pbit_reg checks UNIT bounds/run status and converts a zero seed to one.
    // Node index = {column, row}: left 0..3, right 4..7.
    // ------------------------------------------------------------
    input  logic                                    cfg_node_we_i,
    input  logic [NODE_TARGET_ROW_WIDTH-1:0]         cfg_node_row_i,
    input  logic [NODE_TARGET_COL_WIDTH-1:0]         cfg_node_col_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]         cfg_node_i,
    output logic [NODE_CFG_W-1:0]                   node_rdata_o,

    input  logic                                    cfg_seed_we_i,
    input  logic [SEED_TARGET_NUMBER_WIDTH-1:0]      cfg_seed_number_i,
    input  logic [SEED_WIDTH-1:0]                   cfg_seed_i,
    output logic [SEED_WIDTH-1:0]                   seed_rdata_o,

    input  logic                                    cfg_edge_we_i,
    input  logic                                    cfg_edge_clr_i,
    input  logic [EDGE_TYPE_WIDTH-1:0]              cfg_edge_type_i,
    input  logic [EDGE_TARGET_NUMBER_WIDTH-1:0]     cfg_edge_number_i,
    input  logic [EDGE_CFG_PACKED_WIDTH-1:0]        cfg_edge_i,
    output logic [EDGE_RDATA_PACKED_WIDTH-1:0]      edge_rdata_o,

    // ------------------------------------------------------------
    // Shared BANK thresholds and control. No local phase controller.
    // active_col_i: 0 selects nodes 0..3; 1 selects nodes 4..7.
    // Hold the active column and thresholds through the commit edge.
    // MAC data is registered; sample its result on a later clock edge.
    // All BANKs must submit the same global phase synchronously.
    // ------------------------------------------------------------
    input  logic                                    active_col_i,
    input  logic                                    lfsr_en_i,
    input  logic                                    mac_en_i,
    input  logic                                    spin_sum_en_i,
    input  logic                                    majority_en_i,
    input  wire [LUT_WIDTH-1:0]                     pos_thr_by_abs_i [1:7],
    input  logic [NUM_MAJORITY_WIDTH-1:0]           vote_threshold_i,

    // ------------------------------------------------------------
    // Neighbor spins: up/down use nodes 0..3, left/right use nodes 4..7.
    // Packed spin_o bit n is node n (snapshot order 0..7).
    // ------------------------------------------------------------
    input  logic [3:0]                              up_spin_i,
    input  logic [3:0]                              down_spin_i,
    input  logic [3:0]                              left_spin_i,
    input  logic [3:0]                              right_spin_i,
    output logic [NODE_IN_UNIT-1:0]                  spin_o,

    // Each undirected external edge is stored only by its upper/left owner.
    // Packed edge format is {prob, sign, valid}, as defined in pbit_pkg.
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         up_edge_cfg_i [0:3],
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         left_edge_cfg_i [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         down_edge_cfg_o [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         right_edge_cfg_o [0:3]
);
    // Last array column: 16 internal edges and 4 down edges; no right-edge registers.
    // Keep six edge-type wiring slots; absent slots are constant zero.
    localparam int CELL_ROW_NUM = 4;
    localparam int OWNED_EDGE_TYPE_NUM = 6;

    logic [CELL_ROW_NUM-1:0] node_row_hit_w;
    logic [1:0]             node_col_hit_w;
    logic [CELL_ROW_NUM-1:0] seed_hit_w;
    logic [CELL_ROW_NUM-1:0] edge_number_hit_w;
    logic [OWNED_EDGE_TYPE_NUM-1:0] edge_type_hit_w;
    logic [1:0]             node_commit_w;
    logic [NODE_CFG_W-1:0] node_rcfg_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] node_bias_sign_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] node_bias_prob_w [0:NODE_IN_UNIT-1];

    // Types 0..3: internal_edge[left_row][right_row]. Type 4: right; type 5: down.
    logic [EDGE_CFG_PACKED_WIDTH-1:0] owned_edge_cfg_w [0:OWNED_EDGE_TYPE_NUM-1][0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_a_w [0:OWNED_EDGE_TYPE_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_b_w [0:OWNED_EDGE_TYPE_NUM-1];

    logic [SEED_WIDTH-1:0] rnd32_w [0:CELL_ROW_NUM-1];
    logic signed [MACSUM_WIDTH-1:0] macsum_w [0:CELL_ROW_NUM-1];
    logic [LUT_WIDTH-1:0] p_up_thr_w [0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] majority_spin_w;

    // ------------------------------------------------------------
    // Shared local address decoders and node storage
    // ------------------------------------------------------------
    genvar row, col, edge_type, number, lane;
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_TARGET_ROW
            assign node_row_hit_w[row] = cfg_node_row_i == NODE_TARGET_ROW_WIDTH'(row);
            assign seed_hit_w[row] = cfg_seed_number_i == SEED_TARGET_NUMBER_WIDTH'(row);
            assign edge_number_hit_w[row] = cfg_edge_number_i == EDGE_TARGET_NUMBER_WIDTH'(row);
        end
        for (col = 0; col < 2; col = col + 1) begin : GEN_NODE_COL
            assign node_col_hit_w[col] = cfg_node_col_i == NODE_TARGET_COL_WIDTH'(col);
            assign node_commit_w[col] = majority_en_i && (active_col_i == 1'(col));
            for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_NODE_ROW
                localparam int NODE_IDX = col * CELL_ROW_NUM + row;
                pbit_node u_pbit_node (
                    .clk                 (clk),
                    .rst_n               (rst_n),
                    .local_cfg_node_we_i (cfg_node_we_i && node_col_hit_w[col] && node_row_hit_w[row]),
                    .local_node_cfg_i    (cfg_node_i),
                    .local_node_rcfg_o   (node_rcfg_w[NODE_IDX]),
                    .bias_sign_o         (node_bias_sign_w[NODE_IDX]),
                    .bias_prob_o         (node_bias_prob_w[NODE_IDX]),
                    .majority_en_i       (node_commit_w[col]),
                    .majority_spin_i     (majority_spin_w[row]),
                    .spin_o              (spin_o[NODE_IDX])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // 20 owned edge registers. Both endpoints see the same stored parameters.
    // ------------------------------------------------------------
    generate
        for (edge_type = 0; edge_type < CELL_ROW_NUM; edge_type = edge_type + 1) begin : GEN_EDGE_TYPE
            assign edge_type_hit_w[edge_type] = cfg_edge_type_i == EDGE_TYPE_WIDTH'(edge_type);
            for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_EDGE_NUMBER
                logic target_hit_w;
                logic endpoint_a_w, endpoint_b_w;
                assign target_hit_w = edge_type_hit_w[edge_type] && edge_number_hit_w[number];
                assign endpoint_a_w = spin_o[edge_type];
                assign endpoint_b_w = spin_o[CELL_ROW_NUM+number];
                edge_reg_coupler u_edge_reg_coupler (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .cfg_we_i             (cfg_edge_we_i && target_hit_w),
                    .cfg_clr_pulse_i      (cfg_edge_clr_i && target_hit_w),
                    .cfg_prob_i           (cfg_edge_i[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .cfg_edge_sign_i      (cfg_edge_i[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .cfg_valid_i          (cfg_edge_i[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .pbit_a_spin_i        (endpoint_a_w),
                    .pbit_b_spin_i        (endpoint_b_w),
                    .prob_to_a_o          (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .edge_sign_to_a_o     (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .valid_to_a_o         (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .neighbor_spin_to_a_o (edge_neighbor_a_w[edge_type][number]),
                    .prob_to_b_o          (),
                    .edge_sign_to_b_o     (),
                    .valid_to_b_o         (),
                    .neighbor_spin_to_b_o (edge_neighbor_b_w[edge_type][number])
                );
            end
        end
        // Missing right edges are constants, with no storage or write decoder.
        assign edge_type_hit_w[4] = 1'b0;
        assign edge_neighbor_a_w[4] = '0;
        assign edge_neighbor_b_w[4] = '0;
        for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_NO_RIGHT_EDGE
            assign owned_edge_cfg_w[4][number] = '0;
        end
        assign edge_type_hit_w[5] = cfg_edge_type_i == 3'd5;
        for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_DOWN_EDGE
            logic target_hit_w;
            logic endpoint_a_w, endpoint_b_w;
            assign target_hit_w = edge_type_hit_w[5] && edge_number_hit_w[number];
            assign endpoint_a_w = spin_o[number];
            assign endpoint_b_w = down_spin_i[number];
            edge_reg_coupler u_edge_reg_coupler (
                .clk                  (clk),
                .rst_n                (rst_n),
                .cfg_we_i             (cfg_edge_we_i && target_hit_w),
                .cfg_clr_pulse_i      (cfg_edge_clr_i && target_hit_w),
                .cfg_prob_i           (cfg_edge_i[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                .cfg_edge_sign_i      (cfg_edge_i[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                .cfg_valid_i          (cfg_edge_i[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                .pbit_a_spin_i        (endpoint_a_w),
                .pbit_b_spin_i        (endpoint_b_w),
                .prob_to_a_o          (owned_edge_cfg_w[5][number][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                .edge_sign_to_a_o     (owned_edge_cfg_w[5][number][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                .valid_to_a_o         (owned_edge_cfg_w[5][number][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                .neighbor_spin_to_a_o (edge_neighbor_a_w[5][number]),
                .prob_to_b_o          (),
                .edge_sign_to_b_o     (),
                .valid_to_b_o         (),
                .neighbor_spin_to_b_o (edge_neighbor_b_w[5][number])
            );
        end
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_EDGE_EXPORT
            assign right_edge_cfg_o[row] = owned_edge_cfg_w[4][row];
            assign down_edge_cfg_o[row] = owned_edge_cfg_w[5][row];
        end
    endgenerate

    // ------------------------------------------------------------
    // Four datapaths, each shared by node row and node row+4.
    // The column mux is before the MAC register, with no added pipeline stage.
    // ------------------------------------------------------------
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_DATAPATH
            logic [EDGE_CFG_PACKED_WIDTH-1:0] selected_edge_w [0:MAC_EDGE_NUM-1];
            logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w [0:MAC_EDGE_NUM-1];
            logic [MAC_EDGE_NUM-1:0] edge_valid_w, edge_sign_w, neighbor_spin_w;
            logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign_w;
            logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_w;

            assign bias_sign_w = active_col_i ? node_bias_sign_w[CELL_ROW_NUM+row] : node_bias_sign_w[row];
            assign bias_prob_w = active_col_i ? node_bias_prob_w[CELL_ROW_NUM+row] : node_bias_prob_w[row];
            for (lane = 0; lane < CELL_ROW_NUM; lane = lane + 1) begin : GEN_INTERNAL_LANE
                // Right-column nodes traverse columns of the same K4,4 edge matrix.
                assign selected_edge_w[lane] = active_col_i ? owned_edge_cfg_w[lane][row] : owned_edge_cfg_w[row][lane];
                assign neighbor_spin_w[lane] = active_col_i ? edge_neighbor_b_w[lane][row] : edge_neighbor_a_w[row][lane];
            end
            // Incoming edges belong to the left/upper neighbor; outgoing edges belong here.
            assign selected_edge_w[4] = active_col_i ? left_edge_cfg_i[row] : up_edge_cfg_i[row];
            assign selected_edge_w[5] = active_col_i ? owned_edge_cfg_w[4][row] : owned_edge_cfg_w[5][row];
            assign neighbor_spin_w[4] = active_col_i ? left_spin_i[row] : up_spin_i[row];
            assign neighbor_spin_w[5] = active_col_i ? edge_neighbor_a_w[4][row] : edge_neighbor_a_w[5][row];
            for (lane = 0; lane < MAC_EDGE_NUM; lane = lane + 1) begin : GEN_EDGE_FIELDS
                assign edge_valid_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB];
                assign edge_sign_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB];
                assign edge_prob_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB];
            end

            lfsr32_rng32 u_lfsr32_rng32 (
                .clk       (clk),
                .rst_n     (rst_n),
                .seed_we_i (cfg_seed_we_i && seed_hit_w[row]),
                .seed_i    (cfg_seed_i),
                .en_i      (lfsr_en_i),
                .rnd32_o   (rnd32_w[row])
            );
            mac u_mac (
                .clk             (clk),
                .rnd32_i         (rnd32_w[row]),
                .bias_sign_i     (bias_sign_w),
                .bias_prob_i     (bias_prob_w),
                .neighbor_spin_i (neighbor_spin_w),
                .edge_valid_i    (edge_valid_w),
                .edge_sign_i     (edge_sign_w),
                .edge_prob_i     (edge_prob_w),
                .macsum_en_i     (mac_en_i),
                .macsum_o        (macsum_w[row])
            );
            tanh_threshold_select u_tanh_threshold_select (
                .h_i              (macsum_w[row]),
                .pos_thr_by_abs_i  (pos_thr_by_abs_i),
                .p_up_thr_o       (p_up_thr_w[row])
            );
            comparator_vote u_comparator_vote (
                .clk              (clk),
                .rst_n            (rst_n),
                .rnd32_i          (rnd32_w[row]),
                .p_up_thr_i       (p_up_thr_w[row]),
                .spin_sum_en_i    (spin_sum_en_i),
                .majority_en_i    (majority_en_i),
                .vote_threshold_i (vote_threshold_i),
                .majority_spin_o  (majority_spin_w[row])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Combinational readback. The bus controller captures after APPLY commits.
    // Missing boundary edges and types 6/7 return zero and never accept writes.
    // ------------------------------------------------------------
    assign node_rdata_o = node_rcfg_w[{cfg_node_col_i, cfg_node_row_i}];
    assign seed_rdata_o = rnd32_w[cfg_seed_number_i];
    always @(*) begin
        case (cfg_edge_type_i)
            3'd0: edge_rdata_o = owned_edge_cfg_w[0][cfg_edge_number_i];
            3'd1: edge_rdata_o = owned_edge_cfg_w[1][cfg_edge_number_i];
            3'd2: edge_rdata_o = owned_edge_cfg_w[2][cfg_edge_number_i];
            3'd3: edge_rdata_o = owned_edge_cfg_w[3][cfg_edge_number_i];
            3'd4: edge_rdata_o = owned_edge_cfg_w[4][cfg_edge_number_i];
            3'd5: edge_rdata_o = owned_edge_cfg_w[5][cfg_edge_number_i];
            default: edge_rdata_o = '0;
        endcase
    end
endmodule

// Bottom-right corner: 16 internal edges; no right/down-edge registers.
module unit_cell_corner (
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // Configuration requests have already selected this unit cell.
    // pbit_reg checks UNIT bounds/run status and converts a zero seed to one.
    // Node index = {column, row}: left 0..3, right 4..7.
    // ------------------------------------------------------------
    input  logic                                    cfg_node_we_i,
    input  logic [NODE_TARGET_ROW_WIDTH-1:0]         cfg_node_row_i,
    input  logic [NODE_TARGET_COL_WIDTH-1:0]         cfg_node_col_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]         cfg_node_i,
    output logic [NODE_CFG_W-1:0]                   node_rdata_o,

    input  logic                                    cfg_seed_we_i,
    input  logic [SEED_TARGET_NUMBER_WIDTH-1:0]      cfg_seed_number_i,
    input  logic [SEED_WIDTH-1:0]                   cfg_seed_i,
    output logic [SEED_WIDTH-1:0]                   seed_rdata_o,

    input  logic                                    cfg_edge_we_i,
    input  logic                                    cfg_edge_clr_i,
    input  logic [EDGE_TYPE_WIDTH-1:0]              cfg_edge_type_i,
    input  logic [EDGE_TARGET_NUMBER_WIDTH-1:0]     cfg_edge_number_i,
    input  logic [EDGE_CFG_PACKED_WIDTH-1:0]        cfg_edge_i,
    output logic [EDGE_RDATA_PACKED_WIDTH-1:0]      edge_rdata_o,

    // ------------------------------------------------------------
    // Shared BANK thresholds and control. No local phase controller.
    // active_col_i: 0 selects nodes 0..3; 1 selects nodes 4..7.
    // Hold the active column and thresholds through the commit edge.
    // MAC data is registered; sample its result on a later clock edge.
    // All BANKs must submit the same global phase synchronously.
    // ------------------------------------------------------------
    input  logic                                    active_col_i,
    input  logic                                    lfsr_en_i,
    input  logic                                    mac_en_i,
    input  logic                                    spin_sum_en_i,
    input  logic                                    majority_en_i,
    input  wire [LUT_WIDTH-1:0]                     pos_thr_by_abs_i [1:7],
    input  logic [NUM_MAJORITY_WIDTH-1:0]           vote_threshold_i,

    // ------------------------------------------------------------
    // Neighbor spins: up/down use nodes 0..3, left/right use nodes 4..7.
    // Packed spin_o bit n is node n (snapshot order 0..7).
    // ------------------------------------------------------------
    input  logic [3:0]                              up_spin_i,
    input  logic [3:0]                              down_spin_i,
    input  logic [3:0]                              left_spin_i,
    input  logic [3:0]                              right_spin_i,
    output logic [NODE_IN_UNIT-1:0]                  spin_o,

    // Each undirected external edge is stored only by its upper/left owner.
    // Packed edge format is {prob, sign, valid}, as defined in pbit_pkg.
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         up_edge_cfg_i [0:3],
    input  wire [EDGE_CFG_PACKED_WIDTH-1:0]         left_edge_cfg_i [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         down_edge_cfg_o [0:3],
    output logic [EDGE_CFG_PACKED_WIDTH-1:0]         right_edge_cfg_o [0:3]
);
    // Bottom-right corner: 16 internal edges; no right/down-edge registers.
    // Keep six edge-type wiring slots; absent slots are constant zero.
    localparam int CELL_ROW_NUM = 4;
    localparam int OWNED_EDGE_TYPE_NUM = 6;

    logic [CELL_ROW_NUM-1:0] node_row_hit_w;
    logic [1:0]             node_col_hit_w;
    logic [CELL_ROW_NUM-1:0] seed_hit_w;
    logic [CELL_ROW_NUM-1:0] edge_number_hit_w;
    logic [OWNED_EDGE_TYPE_NUM-1:0] edge_type_hit_w;
    logic [1:0]             node_commit_w;
    logic [NODE_CFG_W-1:0] node_rcfg_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] node_bias_sign_w [0:NODE_IN_UNIT-1];
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] node_bias_prob_w [0:NODE_IN_UNIT-1];

    // Types 0..3: internal_edge[left_row][right_row]. Type 4: right; type 5: down.
    logic [EDGE_CFG_PACKED_WIDTH-1:0] owned_edge_cfg_w [0:OWNED_EDGE_TYPE_NUM-1][0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_a_w [0:OWNED_EDGE_TYPE_NUM-1];
    logic [CELL_ROW_NUM-1:0] edge_neighbor_b_w [0:OWNED_EDGE_TYPE_NUM-1];

    logic [SEED_WIDTH-1:0] rnd32_w [0:CELL_ROW_NUM-1];
    logic signed [MACSUM_WIDTH-1:0] macsum_w [0:CELL_ROW_NUM-1];
    logic [LUT_WIDTH-1:0] p_up_thr_w [0:CELL_ROW_NUM-1];
    logic [CELL_ROW_NUM-1:0] majority_spin_w;

    // ------------------------------------------------------------
    // Shared local address decoders and node storage
    // ------------------------------------------------------------
    genvar row, col, edge_type, number, lane;
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_TARGET_ROW
            assign node_row_hit_w[row] = cfg_node_row_i == NODE_TARGET_ROW_WIDTH'(row);
            assign seed_hit_w[row] = cfg_seed_number_i == SEED_TARGET_NUMBER_WIDTH'(row);
            assign edge_number_hit_w[row] = cfg_edge_number_i == EDGE_TARGET_NUMBER_WIDTH'(row);
        end
        for (col = 0; col < 2; col = col + 1) begin : GEN_NODE_COL
            assign node_col_hit_w[col] = cfg_node_col_i == NODE_TARGET_COL_WIDTH'(col);
            assign node_commit_w[col] = majority_en_i && (active_col_i == 1'(col));
            for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_NODE_ROW
                localparam int NODE_IDX = col * CELL_ROW_NUM + row;
                pbit_node u_pbit_node (
                    .clk                 (clk),
                    .rst_n               (rst_n),
                    .local_cfg_node_we_i (cfg_node_we_i && node_col_hit_w[col] && node_row_hit_w[row]),
                    .local_node_cfg_i    (cfg_node_i),
                    .local_node_rcfg_o   (node_rcfg_w[NODE_IDX]),
                    .bias_sign_o         (node_bias_sign_w[NODE_IDX]),
                    .bias_prob_o         (node_bias_prob_w[NODE_IDX]),
                    .majority_en_i       (node_commit_w[col]),
                    .majority_spin_i     (majority_spin_w[row]),
                    .spin_o              (spin_o[NODE_IDX])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // 16 owned edge registers. Both endpoints see the same stored parameters.
    // ------------------------------------------------------------
    generate
        for (edge_type = 0; edge_type < CELL_ROW_NUM; edge_type = edge_type + 1) begin : GEN_EDGE_TYPE
            assign edge_type_hit_w[edge_type] = cfg_edge_type_i == EDGE_TYPE_WIDTH'(edge_type);
            for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_EDGE_NUMBER
                logic target_hit_w;
                logic endpoint_a_w, endpoint_b_w;
                assign target_hit_w = edge_type_hit_w[edge_type] && edge_number_hit_w[number];
                assign endpoint_a_w = spin_o[edge_type];
                assign endpoint_b_w = spin_o[CELL_ROW_NUM+number];
                edge_reg_coupler u_edge_reg_coupler (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .cfg_we_i             (cfg_edge_we_i && target_hit_w),
                    .cfg_clr_pulse_i      (cfg_edge_clr_i && target_hit_w),
                    .cfg_prob_i           (cfg_edge_i[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .cfg_edge_sign_i      (cfg_edge_i[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .cfg_valid_i          (cfg_edge_i[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .pbit_a_spin_i        (endpoint_a_w),
                    .pbit_b_spin_i        (endpoint_b_w),
                    .prob_to_a_o          (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB]),
                    .edge_sign_to_a_o     (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB]),
                    .valid_to_a_o         (owned_edge_cfg_w[edge_type][number][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB]),
                    .neighbor_spin_to_a_o (edge_neighbor_a_w[edge_type][number]),
                    .prob_to_b_o          (),
                    .edge_sign_to_b_o     (),
                    .valid_to_b_o         (),
                    .neighbor_spin_to_b_o (edge_neighbor_b_w[edge_type][number])
                );
            end
        end
        // Missing right edges are constants, with no storage or write decoder.
        assign edge_type_hit_w[4] = 1'b0;
        assign edge_neighbor_a_w[4] = '0;
        assign edge_neighbor_b_w[4] = '0;
        for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_NO_RIGHT_EDGE
            assign owned_edge_cfg_w[4][number] = '0;
        end
        // Missing down edges are constants, with no storage or write decoder.
        assign edge_type_hit_w[5] = 1'b0;
        assign edge_neighbor_a_w[5] = '0;
        assign edge_neighbor_b_w[5] = '0;
        for (number = 0; number < CELL_ROW_NUM; number = number + 1) begin : GEN_NO_DOWN_EDGE
            assign owned_edge_cfg_w[5][number] = '0;
        end
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_EDGE_EXPORT
            assign right_edge_cfg_o[row] = owned_edge_cfg_w[4][row];
            assign down_edge_cfg_o[row] = owned_edge_cfg_w[5][row];
        end
    endgenerate

    // ------------------------------------------------------------
    // Four datapaths, each shared by node row and node row+4.
    // The column mux is before the MAC register, with no added pipeline stage.
    // ------------------------------------------------------------
    generate
        for (row = 0; row < CELL_ROW_NUM; row = row + 1) begin : GEN_DATAPATH
            logic [EDGE_CFG_PACKED_WIDTH-1:0] selected_edge_w [0:MAC_EDGE_NUM-1];
            logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob_w [0:MAC_EDGE_NUM-1];
            logic [MAC_EDGE_NUM-1:0] edge_valid_w, edge_sign_w, neighbor_spin_w;
            logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0] bias_sign_w;
            logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob_w;

            assign bias_sign_w = active_col_i ? node_bias_sign_w[CELL_ROW_NUM+row] : node_bias_sign_w[row];
            assign bias_prob_w = active_col_i ? node_bias_prob_w[CELL_ROW_NUM+row] : node_bias_prob_w[row];
            for (lane = 0; lane < CELL_ROW_NUM; lane = lane + 1) begin : GEN_INTERNAL_LANE
                // Right-column nodes traverse columns of the same K4,4 edge matrix.
                assign selected_edge_w[lane] = active_col_i ? owned_edge_cfg_w[lane][row] : owned_edge_cfg_w[row][lane];
                assign neighbor_spin_w[lane] = active_col_i ? edge_neighbor_b_w[lane][row] : edge_neighbor_a_w[row][lane];
            end
            // Incoming edges belong to the left/upper neighbor; outgoing edges belong here.
            assign selected_edge_w[4] = active_col_i ? left_edge_cfg_i[row] : up_edge_cfg_i[row];
            assign selected_edge_w[5] = active_col_i ? owned_edge_cfg_w[4][row] : owned_edge_cfg_w[5][row];
            assign neighbor_spin_w[4] = active_col_i ? left_spin_i[row] : up_spin_i[row];
            assign neighbor_spin_w[5] = active_col_i ? edge_neighbor_a_w[4][row] : edge_neighbor_a_w[5][row];
            for (lane = 0; lane < MAC_EDGE_NUM; lane = lane + 1) begin : GEN_EDGE_FIELDS
                assign edge_valid_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB];
                assign edge_sign_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB];
                assign edge_prob_w[lane] = selected_edge_w[lane][EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB];
            end

            lfsr32_rng32 u_lfsr32_rng32 (
                .clk       (clk),
                .rst_n     (rst_n),
                .seed_we_i (cfg_seed_we_i && seed_hit_w[row]),
                .seed_i    (cfg_seed_i),
                .en_i      (lfsr_en_i),
                .rnd32_o   (rnd32_w[row])
            );
            mac u_mac (
                .clk             (clk),
                .rnd32_i         (rnd32_w[row]),
                .bias_sign_i     (bias_sign_w),
                .bias_prob_i     (bias_prob_w),
                .neighbor_spin_i (neighbor_spin_w),
                .edge_valid_i    (edge_valid_w),
                .edge_sign_i     (edge_sign_w),
                .edge_prob_i     (edge_prob_w),
                .macsum_en_i     (mac_en_i),
                .macsum_o        (macsum_w[row])
            );
            tanh_threshold_select u_tanh_threshold_select (
                .h_i              (macsum_w[row]),
                .pos_thr_by_abs_i  (pos_thr_by_abs_i),
                .p_up_thr_o       (p_up_thr_w[row])
            );
            comparator_vote u_comparator_vote (
                .clk              (clk),
                .rst_n            (rst_n),
                .rnd32_i          (rnd32_w[row]),
                .p_up_thr_i       (p_up_thr_w[row]),
                .spin_sum_en_i    (spin_sum_en_i),
                .majority_en_i    (majority_en_i),
                .vote_threshold_i (vote_threshold_i),
                .majority_spin_o  (majority_spin_w[row])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Combinational readback. The bus controller captures after APPLY commits.
    // Missing boundary edges and types 6/7 return zero and never accept writes.
    // ------------------------------------------------------------
    assign node_rdata_o = node_rcfg_w[{cfg_node_col_i, cfg_node_row_i}];
    assign seed_rdata_o = rnd32_w[cfg_seed_number_i];
    always @(*) begin
        case (cfg_edge_type_i)
            3'd0: edge_rdata_o = owned_edge_cfg_w[0][cfg_edge_number_i];
            3'd1: edge_rdata_o = owned_edge_cfg_w[1][cfg_edge_number_i];
            3'd2: edge_rdata_o = owned_edge_cfg_w[2][cfg_edge_number_i];
            3'd3: edge_rdata_o = owned_edge_cfg_w[3][cfg_edge_number_i];
            3'd4: edge_rdata_o = owned_edge_cfg_w[4][cfg_edge_number_i];
            3'd5: edge_rdata_o = owned_edge_cfg_w[5][cfg_edge_number_i];
            default: edge_rdata_o = '0;
        endcase
    end
endmodule

`endif
