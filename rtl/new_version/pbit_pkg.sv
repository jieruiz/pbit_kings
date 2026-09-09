`ifndef PBIT_PKG
`define PBIT_PKG
package pbit_pkg;
    //array parameters
    parameter int ROWS = 20;
    parameter int COLS = 20;
    parameter int NODE_IN_UNIT = 8;
    // Common regional partition for tanh thresholds, pbit_control and vote thresholds.
    // Tile dimensions count unit cells; partial banks are rounded up at array boundaries.
    parameter int BANK_TILE_ROWS = 5;
    parameter int BANK_TILE_COLS = 5;
    parameter int BANK_ROWS = (ROWS + BANK_TILE_ROWS - 1) / BANK_TILE_ROWS;
    parameter int BANK_COLS = (COLS + BANK_TILE_COLS - 1) / BANK_TILE_COLS;
    parameter int BANK_NUM = BANK_ROWS * BANK_COLS;
    parameter int REF_CLK_FREQ_HZ = 25_000_000;
    parameter int CLK_FREQ_HZ = 400_000_000;
    parameter int BAUD_RATE = 1_000_000;
    // PLL configuration UART is independent of the high-speed core UART.
    parameter int PLL_CFG_BAUD_RATE = 1_000_000;
    parameter int PLL_CFG_BYTE_TIMEOUT_MS = 20;
    parameter int N_SPIN = ROWS * COLS * NODE_IN_UNIT;
    parameter int SNAPSHOT_WIDTH = 320;
    parameter int SPIN_RDATA_REG_NUM = SNAPSHOT_WIDTH / 32;
    parameter int SPIN_ADDR_MAX = (N_SPIN + SNAPSHOT_WIDTH - 1) / SNAPSHOT_WIDTH;
    parameter int I0_LEVEL_WIDTH = 5;
    parameter int SWEEP_INTERVAL_WIDTH = 16;
    parameter int NUM_MAJORITY_MAX = 32;
    parameter int MAC_EDGE_NUM = 6;
    parameter int MACSUM_WIDTH = $clog2(MAC_EDGE_NUM + 2) + 1;
    parameter int LUT_WIDTH = 16;
    parameter int PBIT_8EDGE_COMPUTE_WIDTH = 5;
    parameter int SWEEP_ROUND_NUM = 32;
    parameter int SWEEP_ROUND_WIDTH = $clog2(SWEEP_ROUND_NUM);
    // Unit target reg
    parameter logic [15:0] A_UNIT_TARGET = 16'h0074;
    parameter UNIT_TARGET_ROW_WIDTH = $clog2(ROWS);
    parameter UNIT_TARGET_ROW_LSB = 0;
    parameter UNIT_TARGET_ROW_MSB = UNIT_TARGET_ROW_LSB + UNIT_TARGET_ROW_WIDTH - 1;
    parameter UNIT_TARGET_COL_WIDTH = $clog2(COLS);
    parameter UNIT_TARGET_COL_LSB = 8;
    parameter UNIT_TARGET_COL_MSB = UNIT_TARGET_COL_LSB + UNIT_TARGET_COL_WIDTH - 1;

    parameter UNIT_TARGET_PACKED_WIDTH = UNIT_TARGET_ROW_WIDTH + UNIT_TARGET_COL_WIDTH;
    parameter UNIT_TARGET_ROW_PACKED_LSB = 0;
    parameter UNIT_TARGET_ROW_PACKED_MSB = UNIT_TARGET_ROW_PACKED_LSB + UNIT_TARGET_ROW_WIDTH - 1;
    parameter UNIT_TARGET_COL_PACKED_LSB = UNIT_TARGET_ROW_PACKED_MSB + 1;
    parameter UNIT_TARGET_COL_PACKED_MSB = UNIT_TARGET_COL_PACKED_LSB + UNIT_TARGET_COL_WIDTH - 1;

    // Node target reg
    parameter logic [15:0] A_NODE_TARGET = 16'h0078;
    parameter NODE_TARGET_ROW_WIDTH = 2;
    parameter NODE_TARGET_ROW_LSB = 0;
    parameter NODE_TARGET_ROW_MSB = NODE_TARGET_ROW_LSB + NODE_TARGET_ROW_WIDTH - 1;
    parameter NODE_TARGET_COL_WIDTH = 1;
    parameter NODE_TARGET_COL_LSB = 8;
    parameter NODE_TARGET_COL_MSB = NODE_TARGET_COL_LSB + NODE_TARGET_COL_WIDTH - 1;

    parameter NODE_TARGET_PACKED_WIDTH = NODE_TARGET_ROW_WIDTH + NODE_TARGET_COL_WIDTH;
    parameter NODE_TARGET_ROW_PACKED_LSB = 0;
    parameter NODE_TARGET_ROW_PACKED_MSB = NODE_TARGET_ROW_PACKED_LSB + NODE_TARGET_ROW_WIDTH - 1;
    parameter NODE_TARGET_COL_PACKED_LSB = NODE_TARGET_ROW_PACKED_MSB + 1;
    parameter NODE_TARGET_COL_PACKED_MSB = NODE_TARGET_COL_PACKED_LSB + NODE_TARGET_COL_WIDTH - 1;

    // Node cfg reg
    parameter logic [15:0] A_NODE_CFG = 16'h007C;
    parameter INIT_VALID_WIDTH = 1;
    parameter INIT_VALID_LSB = 0;
    parameter INIT_VALID_MSB = INIT_VALID_LSB + INIT_VALID_WIDTH - 1;
    parameter CLAMP_VALID_WIDTH = 1;
    parameter CLAMP_VALID_LSB = 1;
    parameter CLAMP_VALID_MSB = CLAMP_VALID_LSB + CLAMP_VALID_WIDTH - 1;
    parameter BIAS_VALID_WIDTH = 1;
    parameter BIAS_VALID_LSB = 2;
    parameter BIAS_VALID_MSB = BIAS_VALID_LSB + BIAS_VALID_WIDTH - 1;
    parameter NODE_CFG_INIT_SPIN_WIDTH = 1;
    parameter NODE_CFG_INIT_SPIN_LSB = 8;
    parameter NODE_CFG_INIT_SPIN_MSB = NODE_CFG_INIT_SPIN_LSB + NODE_CFG_INIT_SPIN_WIDTH - 1;
    parameter NODE_CFG_CLAMP_EN_WIDTH = 1;
    parameter NODE_CFG_CLAMP_EN_LSB = 9;
    parameter NODE_CFG_CLAMP_EN_MSB = NODE_CFG_CLAMP_EN_LSB + NODE_CFG_CLAMP_EN_WIDTH - 1;
    parameter NODE_CFG_CLAMP_SPIN_WIDTH = 1;
    parameter NODE_CFG_CLAMP_SPIN_LSB = 10;
    parameter NODE_CFG_CLAMP_SPIN_MSB = NODE_CFG_CLAMP_SPIN_LSB + NODE_CFG_CLAMP_SPIN_WIDTH - 1;
    parameter NODE_CFG_BIAS_SIGN_WIDTH = 1;
    parameter NODE_CFG_BIAS_SIGN_LSB = 11;
    parameter NODE_CFG_BIAS_SIGN_MSB = NODE_CFG_BIAS_SIGN_LSB + NODE_CFG_BIAS_SIGN_WIDTH - 1;
    parameter NODE_CFG_BIAS_PROB_WIDTH = 7;
    parameter NODE_CFG_BIAS_PROB_LSB = 12;
    parameter NODE_CFG_BIAS_PROB_MSB = NODE_CFG_BIAS_PROB_LSB + NODE_CFG_BIAS_PROB_WIDTH - 1;

    parameter NODE_CFG_W = NODE_CFG_INIT_SPIN_WIDTH + NODE_CFG_CLAMP_EN_WIDTH + NODE_CFG_CLAMP_SPIN_WIDTH + NODE_CFG_BIAS_SIGN_WIDTH + NODE_CFG_BIAS_PROB_WIDTH;
    parameter NODE_CFG_VALID_W = INIT_VALID_WIDTH + CLAMP_VALID_WIDTH + BIAS_VALID_WIDTH;
    parameter NODE_CFG_PACKED_WIDTH = NODE_CFG_VALID_W + NODE_CFG_W;
    parameter INIT_VALID_PACKED_LSB = 0;
    parameter INIT_VALID_PACKED_MSB = INIT_VALID_PACKED_LSB + INIT_VALID_WIDTH - 1;
    parameter CLAMP_VALID_PACKED_LSB = INIT_VALID_PACKED_MSB + 1;
    parameter CLAMP_VALID_PACKED_MSB = CLAMP_VALID_PACKED_LSB + CLAMP_VALID_WIDTH - 1;
    parameter BIAS_VALID_PACKED_LSB = CLAMP_VALID_PACKED_MSB + 1;
    parameter BIAS_VALID_PACKED_MSB = BIAS_VALID_PACKED_LSB + BIAS_VALID_WIDTH - 1;
    parameter NODE_CFG_INIT_SPIN_PACKED_LSB = BIAS_VALID_PACKED_MSB + 1;
    parameter NODE_CFG_INIT_SPIN_PACKED_MSB = NODE_CFG_INIT_SPIN_PACKED_LSB + NODE_CFG_INIT_SPIN_WIDTH - 1;
    parameter NODE_CFG_CLAMP_EN_PACKED_LSB = NODE_CFG_INIT_SPIN_PACKED_MSB + 1;
    parameter NODE_CFG_CLAMP_EN_PACKED_MSB = NODE_CFG_CLAMP_EN_PACKED_LSB + NODE_CFG_CLAMP_EN_WIDTH - 1;
    parameter NODE_CFG_CLAMP_SPIN_PACKED_LSB = NODE_CFG_CLAMP_EN_PACKED_MSB + 1;
    parameter NODE_CFG_CLAMP_SPIN_PACKED_MSB = NODE_CFG_CLAMP_SPIN_PACKED_LSB + NODE_CFG_CLAMP_SPIN_WIDTH - 1;
    parameter NODE_CFG_BIAS_SIGN_PACKED_LSB = NODE_CFG_CLAMP_SPIN_PACKED_MSB + 1;
    parameter NODE_CFG_BIAS_SIGN_PACKED_MSB = NODE_CFG_BIAS_SIGN_PACKED_LSB + NODE_CFG_BIAS_SIGN_WIDTH - 1;
    parameter NODE_CFG_BIAS_PROB_PACKED_LSB = NODE_CFG_BIAS_SIGN_PACKED_MSB + 1;
    parameter NODE_CFG_BIAS_PROB_PACKED_MSB = NODE_CFG_BIAS_PROB_PACKED_LSB + NODE_CFG_BIAS_PROB_WIDTH - 1;

    // Seed target reg
    parameter logic [15:0] A_SEED_TARGET = 16'h0088;
    parameter SEED_TARGET_NUMBER_WIDTH = 2;
    parameter SEED_TARGET_NUMBER_LSB = 0;
    parameter SEED_TARGET_NUMBER_MSB = SEED_TARGET_NUMBER_LSB + SEED_TARGET_NUMBER_WIDTH - 1;

    parameter SEED_TARGET_PACKED_WIDTH = SEED_TARGET_NUMBER_WIDTH;
    parameter SEED_TARGET_NUMBER_PACKED_LSB = 0;
    parameter SEED_TARGET_NUMBER_PACKED_MSB = SEED_TARGET_NUMBER_PACKED_LSB + SEED_TARGET_NUMBER_WIDTH - 1;

    // Seed reg
    parameter logic [15:0] A_SEED = 16'h008C;
    parameter SEED_WIDTH = 32;
    parameter SEED_LSB = 0;
    parameter SEED_MSB = SEED_LSB + SEED_WIDTH - 1;

    parameter SEED_PACKED_WIDTH = SEED_WIDTH;
    parameter SEED_PACKED_LSB = 0;
    parameter SEED_PACKED_MSB = SEED_PACKED_LSB + SEED_WIDTH - 1;

    // Seed cmd reg
    parameter logic [15:0] A_SEED_CMD = 16'h0090;
    parameter APPLY_SEED_WIDTH = 1;
    parameter APPLY_SEED_LSB = 0;
    parameter APPLY_SEED_MSB = APPLY_SEED_LSB + APPLY_SEED_WIDTH - 1;
    parameter READBACK_SEED_WIDTH = 1;
    parameter READBACK_SEED_LSB = 1;
    parameter READBACK_SEED_MSB = READBACK_SEED_LSB + READBACK_SEED_WIDTH - 1;

    parameter SEED_CMD_PACKED_WIDTH = APPLY_SEED_WIDTH + READBACK_SEED_WIDTH;
    parameter APPLY_SEED_PACKED_LSB = 0;
    parameter APPLY_SEED_PACKED_MSB = APPLY_SEED_PACKED_LSB + APPLY_SEED_WIDTH - 1;
    parameter READBACK_SEED_PACKED_LSB = APPLY_SEED_PACKED_MSB + 1;
    parameter READBACK_SEED_PACKED_MSB = READBACK_SEED_PACKED_LSB + READBACK_SEED_WIDTH - 1;

    // Edge target reg; EDGE_TYPE encodings are not specified in the register table.
    parameter logic [15:0] A_EDGE_TARGET = 16'h0098;
    parameter EDGE_TYPE_WIDTH = 3;
    parameter EDGE_TYPE_LSB = 0;
    parameter EDGE_TYPE_MSB = EDGE_TYPE_LSB + EDGE_TYPE_WIDTH - 1;
    parameter EDGE_TARGET_NUMBER_WIDTH = 2;
    parameter EDGE_TARGET_NUMBER_LSB = 8;
    parameter EDGE_TARGET_NUMBER_MSB = EDGE_TARGET_NUMBER_LSB + EDGE_TARGET_NUMBER_WIDTH - 1;

    parameter EDGE_TARGET_PACKED_WIDTH = EDGE_TYPE_WIDTH + EDGE_TARGET_NUMBER_WIDTH;
    parameter EDGE_TYPE_PACKED_LSB = 0;
    parameter EDGE_TYPE_PACKED_MSB = EDGE_TYPE_PACKED_LSB + EDGE_TYPE_WIDTH - 1;
    parameter EDGE_TARGET_NUMBER_PACKED_LSB = EDGE_TYPE_PACKED_MSB + 1;
    parameter EDGE_TARGET_NUMBER_PACKED_MSB = EDGE_TARGET_NUMBER_PACKED_LSB + EDGE_TARGET_NUMBER_WIDTH - 1;

    // Edge cfg reg
    parameter logic [15:0] A_EDGE_CFG = 16'h009C;
    parameter EDGE_CFG_EDGE_VALID_WIDTH = 1;
    parameter EDGE_CFG_EDGE_VALID_LSB = 0;
    parameter EDGE_CFG_EDGE_VALID_MSB = EDGE_CFG_EDGE_VALID_LSB + EDGE_CFG_EDGE_VALID_WIDTH - 1;
    parameter EDGE_CFG_EDGE_SIGN_WIDTH = 1;
    parameter EDGE_CFG_EDGE_SIGN_LSB = 1;
    parameter EDGE_CFG_EDGE_SIGN_MSB = EDGE_CFG_EDGE_SIGN_LSB + EDGE_CFG_EDGE_SIGN_WIDTH - 1;
    parameter EDGE_CFG_EDGE_PROB_WIDTH = 7;
    parameter EDGE_CFG_EDGE_PROB_LSB = 2;
    parameter EDGE_CFG_EDGE_PROB_MSB = EDGE_CFG_EDGE_PROB_LSB + EDGE_CFG_EDGE_PROB_WIDTH - 1;

    parameter EDGE_CFG_PACKED_WIDTH = EDGE_CFG_EDGE_VALID_WIDTH + EDGE_CFG_EDGE_SIGN_WIDTH + EDGE_CFG_EDGE_PROB_WIDTH;
    parameter EDGE_CFG_EDGE_VALID_PACKED_LSB = 0;
    parameter EDGE_CFG_EDGE_VALID_PACKED_MSB = EDGE_CFG_EDGE_VALID_PACKED_LSB + EDGE_CFG_EDGE_VALID_WIDTH - 1;
    parameter EDGE_CFG_EDGE_SIGN_PACKED_LSB = EDGE_CFG_EDGE_VALID_PACKED_MSB + 1;
    parameter EDGE_CFG_EDGE_SIGN_PACKED_MSB = EDGE_CFG_EDGE_SIGN_PACKED_LSB + EDGE_CFG_EDGE_SIGN_WIDTH - 1;
    parameter EDGE_CFG_EDGE_PROB_PACKED_LSB = EDGE_CFG_EDGE_SIGN_PACKED_MSB + 1;
    parameter EDGE_CFG_EDGE_PROB_PACKED_MSB = EDGE_CFG_EDGE_PROB_PACKED_LSB + EDGE_CFG_EDGE_PROB_WIDTH - 1;

    // Snapshot addr reg
    parameter logic [15:0] A_SNAPSHOT_ADDR = 16'h0010;
    // Derive page address width; the current configuration uses four bits for pages 0..9.
    parameter SNAPSHOT_ADDR_WIDTH = (SPIN_ADDR_MAX <= 1) ? 1 : $clog2(SPIN_ADDR_MAX);
    parameter SNAPSHOT_ADDR_LSB = 0;
    parameter SNAPSHOT_ADDR_MSB = SNAPSHOT_ADDR_LSB + SNAPSHOT_ADDR_WIDTH - 1;

    parameter SNAPSHOT_ADDR_PACKED_WIDTH = SNAPSHOT_ADDR_WIDTH;
    parameter SNAPSHOT_ADDR_PACKED_LSB = 0;
    parameter SNAPSHOT_ADDR_PACKED_MSB = SNAPSHOT_ADDR_PACKED_LSB + SNAPSHOT_ADDR_WIDTH - 1;

    parameter I0_LEVEL_REG_NUM = SWEEP_ROUND_NUM / 4;
    // I0 level0 reg
    parameter logic [15:0] A_I0_LEVEL0 = 16'h0014;
    // I0 level1 reg
    parameter logic [15:0] A_I0_LEVEL1 = 16'h0018;
    // I0 level2 reg
    parameter logic [15:0] A_I0_LEVEL2 = 16'h001C;
    // I0 level3 reg
    parameter logic [15:0] A_I0_LEVEL3 = 16'h0020;
    // I0 level4 reg
    parameter logic [15:0] A_I0_LEVEL4 = 16'h0024;
    // I0 level5 reg
    parameter logic [15:0] A_I0_LEVEL5 = 16'h0028;
    // I0 level6 reg
    parameter logic [15:0] A_I0_LEVEL6 = 16'h002C;
    // I0 level7 reg
    parameter logic [15:0] A_I0_LEVEL7 = 16'h0030;
    
    parameter I0_LEVEL0_WIDTH = I0_LEVEL_WIDTH;
    parameter I0_LEVEL0_LSB = 0;
    parameter I0_LEVEL0_MSB = I0_LEVEL0_LSB + I0_LEVEL0_WIDTH - 1;
    parameter I0_LEVEL1_WIDTH = I0_LEVEL_WIDTH;
    parameter I0_LEVEL1_LSB = 8;
    parameter I0_LEVEL1_MSB = I0_LEVEL1_LSB + I0_LEVEL1_WIDTH - 1;
    parameter I0_LEVEL2_WIDTH = I0_LEVEL_WIDTH;
    parameter I0_LEVEL2_LSB = 16;
    parameter I0_LEVEL2_MSB = I0_LEVEL2_LSB + I0_LEVEL2_WIDTH - 1;
    parameter I0_LEVEL3_WIDTH = I0_LEVEL_WIDTH;
    parameter I0_LEVEL3_LSB = 24;
    parameter I0_LEVEL3_MSB = I0_LEVEL3_LSB + I0_LEVEL3_WIDTH - 1;
    parameter I0_LEVEL_PACKED_WIDTH = I0_LEVEL0_WIDTH + I0_LEVEL1_WIDTH + I0_LEVEL2_WIDTH + I0_LEVEL3_WIDTH;
    parameter I0_LEVEL0_PACKED_LSB = 0;
    parameter I0_LEVEL0_PACKED_MSB = I0_LEVEL0_PACKED_LSB + I0_LEVEL0_WIDTH - 1;
    parameter I0_LEVEL1_PACKED_LSB = I0_LEVEL0_PACKED_MSB + 1;
    parameter I0_LEVEL1_PACKED_MSB = I0_LEVEL1_PACKED_LSB + I0_LEVEL1_WIDTH - 1;
    parameter I0_LEVEL2_PACKED_LSB = I0_LEVEL1_PACKED_MSB + 1;
    parameter I0_LEVEL2_PACKED_MSB = I0_LEVEL2_PACKED_LSB + I0_LEVEL2_WIDTH - 1;
    parameter I0_LEVEL3_PACKED_LSB = I0_LEVEL2_PACKED_MSB + 1;
    parameter I0_LEVEL3_PACKED_MSB = I0_LEVEL3_PACKED_LSB + I0_LEVEL3_WIDTH - 1;

    parameter int SWEEP_INTERVAL_REG_NUM = SWEEP_ROUND_NUM / 2;
    // Sweep interval0 reg
    parameter logic [15:0] A_SWEEP_INTERVAL0 = 16'h0034;
    // Sweep interval1 reg
    parameter logic [15:0] A_SWEEP_INTERVAL1 = 16'h0038;
    // Sweep interval2 reg
    parameter logic [15:0] A_SWEEP_INTERVAL2 = 16'h003C;
    // Sweep interval3 reg
    parameter logic [15:0] A_SWEEP_INTERVAL3 = 16'h0040;
    // Sweep interval4 reg
    parameter logic [15:0] A_SWEEP_INTERVAL4 = 16'h0044;
    // Sweep interval5 reg
    parameter logic [15:0] A_SWEEP_INTERVAL5 = 16'h0048;
    // Sweep interval6 reg
    parameter logic [15:0] A_SWEEP_INTERVAL6 = 16'h004C;
    // Sweep interval7 reg
    parameter logic [15:0] A_SWEEP_INTERVAL7 = 16'h0050;
    // Sweep interval8 reg
    parameter logic [15:0] A_SWEEP_INTERVAL8 = 16'h0054;
    // Sweep interval9 reg
    parameter logic [15:0] A_SWEEP_INTERVAL9 = 16'h0058;
    // Sweep interval10 reg
    parameter logic [15:0] A_SWEEP_INTERVAL10 = 16'h005C;
    // Sweep interval11 reg
    parameter logic [15:0] A_SWEEP_INTERVAL11 = 16'h0060;
    // Sweep interval12 reg
    parameter logic [15:0] A_SWEEP_INTERVAL12 = 16'h0064;
    // Sweep interval13 reg
    parameter logic [15:0] A_SWEEP_INTERVAL13 = 16'h0068;
    // Sweep interval14 reg
    parameter logic [15:0] A_SWEEP_INTERVAL14 = 16'h006C;
    // Sweep interval15 reg
    parameter logic [15:0] A_SWEEP_INTERVAL15 = 16'h0070;
    parameter SWEEP_INTERVAL0_WIDTH = 16;
    parameter SWEEP_INTERVAL0_LSB = 0;
    parameter SWEEP_INTERVAL0_MSB = SWEEP_INTERVAL0_LSB + SWEEP_INTERVAL0_WIDTH - 1;
    parameter SWEEP_INTERVAL1_WIDTH = 16;
    parameter SWEEP_INTERVAL1_LSB = 16;
    parameter SWEEP_INTERVAL1_MSB = SWEEP_INTERVAL1_LSB + SWEEP_INTERVAL1_WIDTH - 1;
    parameter SWEEP_INTERVAL_PACKED_WIDTH = SWEEP_INTERVAL0_WIDTH + SWEEP_INTERVAL1_WIDTH;
    parameter SWEEP_INTERVAL0_PACKED_LSB = 0;
    parameter SWEEP_INTERVAL0_PACKED_MSB = SWEEP_INTERVAL0_PACKED_LSB + SWEEP_INTERVAL0_WIDTH - 1;
    parameter SWEEP_INTERVAL1_PACKED_LSB = SWEEP_INTERVAL0_PACKED_MSB + 1;
    parameter SWEEP_INTERVAL1_PACKED_MSB = SWEEP_INTERVAL1_PACKED_LSB + SWEEP_INTERVAL1_WIDTH - 1;

    // Global cfg reg
    parameter logic [15:0] A_GLOBAL_CFG = 16'h0004;
    parameter NUM_SWEEP_WIDTH = 24;
    parameter NUM_SWEEP_LSB = 0;
    parameter NUM_SWEEP_MSB = NUM_SWEEP_LSB + NUM_SWEEP_WIDTH - 1;
    parameter NUM_MAJORITY_WIDTH = $clog2(NUM_MAJORITY_MAX);
    parameter NUM_MAJORITY_LSB = 24;
    parameter NUM_MAJORITY_MSB = NUM_MAJORITY_LSB + NUM_MAJORITY_WIDTH - 1;

    parameter GLOBAL_CFG_PACKED_WIDTH = NUM_SWEEP_WIDTH + NUM_MAJORITY_WIDTH;
    parameter NUM_SWEEP_PACKED_LSB = 0;
    parameter NUM_SWEEP_PACKED_MSB = NUM_SWEEP_PACKED_LSB + NUM_SWEEP_WIDTH - 1;
    parameter NUM_MAJORITY_PACKED_LSB = NUM_SWEEP_PACKED_MSB + 1;
    parameter NUM_MAJORITY_PACKED_MSB = NUM_MAJORITY_PACKED_LSB + NUM_MAJORITY_WIDTH - 1;

    // Global ctrl reg
    parameter logic [15:0] A_GLOBAL_CTRL = 16'h0000;
    parameter CFG_DONE_SET_WIDTH = 1;
    parameter CFG_DONE_SET_LSB = 0;
    parameter CFG_DONE_SET_MSB = CFG_DONE_SET_LSB + CFG_DONE_SET_WIDTH - 1;
    parameter CFG_DONE_CLEAR_WIDTH = 1;
    parameter CFG_DONE_CLEAR_LSB = 1;
    parameter CFG_DONE_CLEAR_MSB = CFG_DONE_CLEAR_LSB + CFG_DONE_CLEAR_WIDTH - 1;
    parameter RUN_START_WIDTH = 1;
    parameter RUN_START_LSB = 2;
    parameter RUN_START_MSB = RUN_START_LSB + RUN_START_WIDTH - 1;
    parameter SNAPSHOT_LATCH_WIDTH = 1;
    parameter SNAPSHOT_LATCH_LSB = 3;
    parameter SNAPSHOT_LATCH_MSB = SNAPSHOT_LATCH_LSB + SNAPSHOT_LATCH_WIDTH - 1;
    parameter RUN_DONE_CLEAR_WIDTH = 1;
    parameter RUN_DONE_CLEAR_LSB = 4;
    parameter RUN_DONE_CLEAR_MSB = RUN_DONE_CLEAR_LSB + RUN_DONE_CLEAR_WIDTH - 1;
    parameter ERROR_CLEAR_WIDTH = 1;
    parameter ERROR_CLEAR_LSB = 5;
    parameter ERROR_CLEAR_MSB = ERROR_CLEAR_LSB + ERROR_CLEAR_WIDTH - 1;

    parameter GLOBAL_CTRL_PACKED_WIDTH = CFG_DONE_SET_WIDTH + CFG_DONE_CLEAR_WIDTH + RUN_START_WIDTH + SNAPSHOT_LATCH_WIDTH + RUN_DONE_CLEAR_WIDTH + ERROR_CLEAR_WIDTH;
    parameter CFG_DONE_SET_PACKED_LSB = 0;
    parameter CFG_DONE_SET_PACKED_MSB = CFG_DONE_SET_PACKED_LSB + CFG_DONE_SET_WIDTH - 1;
    parameter CFG_DONE_CLEAR_PACKED_LSB = CFG_DONE_SET_PACKED_MSB + 1;
    parameter CFG_DONE_CLEAR_PACKED_MSB = CFG_DONE_CLEAR_PACKED_LSB + CFG_DONE_CLEAR_WIDTH - 1;
    parameter RUN_START_PACKED_LSB = CFG_DONE_CLEAR_PACKED_MSB + 1;
    parameter RUN_START_PACKED_MSB = RUN_START_PACKED_LSB + RUN_START_WIDTH - 1;
    parameter SNAPSHOT_LATCH_PACKED_LSB = RUN_START_PACKED_MSB + 1;
    parameter SNAPSHOT_LATCH_PACKED_MSB = SNAPSHOT_LATCH_PACKED_LSB + SNAPSHOT_LATCH_WIDTH - 1;
    parameter RUN_DONE_CLEAR_PACKED_LSB = SNAPSHOT_LATCH_PACKED_MSB + 1;
    parameter RUN_DONE_CLEAR_PACKED_MSB = RUN_DONE_CLEAR_PACKED_LSB + RUN_DONE_CLEAR_WIDTH - 1;
    parameter ERROR_CLEAR_PACKED_LSB = RUN_DONE_CLEAR_PACKED_MSB + 1;
    parameter ERROR_CLEAR_PACKED_MSB = ERROR_CLEAR_PACKED_LSB + ERROR_CLEAR_WIDTH - 1;

    // Node cmd reg
    parameter logic [15:0] A_NODE_CMD = 16'h0080;
    parameter APPLY_CFG_WIDTH = 1;
    parameter APPLY_CFG_LSB = 0;
    parameter APPLY_CFG_MSB = APPLY_CFG_LSB + APPLY_CFG_WIDTH - 1;
    parameter READBACK_CFG_WIDTH = 1;
    parameter READBACK_CFG_LSB = 1;
    parameter READBACK_CFG_MSB = READBACK_CFG_LSB + READBACK_CFG_WIDTH - 1;

    parameter NODE_CMD_PACKED_WIDTH = APPLY_CFG_WIDTH + READBACK_CFG_WIDTH;
    parameter APPLY_CFG_PACKED_LSB = 0;
    parameter APPLY_CFG_PACKED_MSB = APPLY_CFG_PACKED_LSB + APPLY_CFG_WIDTH - 1;
    parameter READBACK_CFG_PACKED_LSB = APPLY_CFG_PACKED_MSB + 1;
    parameter READBACK_CFG_PACKED_MSB = READBACK_CFG_PACKED_LSB + READBACK_CFG_WIDTH - 1;

    // Edge cmd reg
    parameter logic [15:0] A_EDGE_CMD = 16'h00A0;
    parameter APPLY_EDGE_WIDTH = 1;
    parameter APPLY_EDGE_LSB = 0;
    parameter APPLY_EDGE_MSB = APPLY_EDGE_LSB + APPLY_EDGE_WIDTH - 1;
    parameter CLEAR_EDGE_WIDTH = 1;
    parameter CLEAR_EDGE_LSB = 1;
    parameter CLEAR_EDGE_MSB = CLEAR_EDGE_LSB + CLEAR_EDGE_WIDTH - 1;
    parameter READBACK_EDGE_WIDTH = 1;
    parameter READBACK_EDGE_LSB = 2;
    parameter READBACK_EDGE_MSB = READBACK_EDGE_LSB + READBACK_EDGE_WIDTH - 1;

    parameter EDGE_CMD_PACKED_WIDTH = APPLY_EDGE_WIDTH + CLEAR_EDGE_WIDTH + READBACK_EDGE_WIDTH;
    parameter APPLY_EDGE_PACKED_LSB = 0;
    parameter APPLY_EDGE_PACKED_MSB = APPLY_EDGE_PACKED_LSB + APPLY_EDGE_WIDTH - 1;
    parameter CLEAR_EDGE_PACKED_LSB = APPLY_EDGE_PACKED_MSB + 1;
    parameter CLEAR_EDGE_PACKED_MSB = CLEAR_EDGE_PACKED_LSB + CLEAR_EDGE_WIDTH - 1;
    parameter READBACK_EDGE_PACKED_LSB = CLEAR_EDGE_PACKED_MSB + 1;
    parameter READBACK_EDGE_PACKED_MSB = READBACK_EDGE_PACKED_LSB + READBACK_EDGE_WIDTH - 1;

 // Global status reg
    parameter logic [15:0] A_GLOBAL_STATUS = 16'h0008;
    parameter CFG_DONE_WIDTH = 1;
    parameter CFG_DONE_LSB = 0;
    parameter CFG_DONE_MSB = CFG_DONE_LSB + CFG_DONE_WIDTH - 1;
    parameter RUN_BUSY_WIDTH = 1;
    parameter RUN_BUSY_LSB = 1;
    parameter RUN_BUSY_MSB = RUN_BUSY_LSB + RUN_BUSY_WIDTH - 1;
    parameter RUN_DONE_WIDTH = 1;
    parameter RUN_DONE_LSB = 2;
    parameter RUN_DONE_MSB = RUN_DONE_LSB + RUN_DONE_WIDTH - 1;
    parameter NODE_CMD_DONE_WIDTH = 1;
    parameter NODE_CMD_DONE_LSB = 3;
    parameter NODE_CMD_DONE_MSB = NODE_CMD_DONE_LSB + NODE_CMD_DONE_WIDTH - 1;
    parameter EDGE_CMD_DONE_WIDTH = 1;
    parameter EDGE_CMD_DONE_LSB = 4;
    parameter EDGE_CMD_DONE_MSB = EDGE_CMD_DONE_LSB + EDGE_CMD_DONE_WIDTH - 1;
    // RC on GLOBAL_STATUS read; a simultaneous new snapshot capture wins.
    parameter SNAPSHOT_VALID_WIDTH = 1;
    parameter SNAPSHOT_VALID_LSB = 5;
    parameter SNAPSHOT_VALID_MSB = SNAPSHOT_VALID_LSB + SNAPSHOT_VALID_WIDTH - 1;
    parameter ERROR_WIDTH = 1;
    parameter ERROR_LSB = 6;
    parameter ERROR_MSB = ERROR_LSB + ERROR_WIDTH - 1;

    parameter SEED_CMD_DONE_WIDTH = 1;
    parameter SEED_CMD_DONE_LSB = 7;
    parameter SEED_CMD_DONE_MSB = SEED_CMD_DONE_LSB + SEED_CMD_DONE_WIDTH - 1;
    parameter CFG_BUSY_WIDTH = 1;
    parameter CFG_BUSY_LSB = 8;
    parameter CFG_BUSY_MSB = CFG_BUSY_LSB + CFG_BUSY_WIDTH - 1;

    parameter GLOBAL_STATUS_PACKED_WIDTH = CFG_DONE_WIDTH + RUN_BUSY_WIDTH + RUN_DONE_WIDTH + NODE_CMD_DONE_WIDTH + EDGE_CMD_DONE_WIDTH + SNAPSHOT_VALID_WIDTH + ERROR_WIDTH + SEED_CMD_DONE_WIDTH + CFG_BUSY_WIDTH;
    parameter CFG_DONE_PACKED_LSB = 0;
    parameter CFG_DONE_PACKED_MSB = CFG_DONE_PACKED_LSB + CFG_DONE_WIDTH - 1;
    parameter RUN_BUSY_PACKED_LSB = CFG_DONE_PACKED_MSB + 1;
    parameter RUN_BUSY_PACKED_MSB = RUN_BUSY_PACKED_LSB + RUN_BUSY_WIDTH - 1;
    parameter RUN_DONE_PACKED_LSB = RUN_BUSY_PACKED_MSB + 1;
    parameter RUN_DONE_PACKED_MSB = RUN_DONE_PACKED_LSB + RUN_DONE_WIDTH - 1;
    parameter NODE_CMD_DONE_PACKED_LSB = RUN_DONE_PACKED_MSB + 1;
    parameter NODE_CMD_DONE_PACKED_MSB = NODE_CMD_DONE_PACKED_LSB + NODE_CMD_DONE_WIDTH - 1;
    parameter EDGE_CMD_DONE_PACKED_LSB = NODE_CMD_DONE_PACKED_MSB + 1;
    parameter EDGE_CMD_DONE_PACKED_MSB = EDGE_CMD_DONE_PACKED_LSB + EDGE_CMD_DONE_WIDTH - 1;
    parameter SNAPSHOT_VALID_PACKED_LSB = EDGE_CMD_DONE_PACKED_MSB + 1;
    parameter SNAPSHOT_VALID_PACKED_MSB = SNAPSHOT_VALID_PACKED_LSB + SNAPSHOT_VALID_WIDTH - 1;
    parameter ERROR_PACKED_LSB = SNAPSHOT_VALID_PACKED_MSB + 1;
    parameter ERROR_PACKED_MSB = ERROR_PACKED_LSB + ERROR_WIDTH - 1;
    parameter SEED_CMD_DONE_PACKED_LSB = ERROR_PACKED_MSB + 1;
    parameter SEED_CMD_DONE_PACKED_MSB = SEED_CMD_DONE_PACKED_LSB + SEED_CMD_DONE_WIDTH - 1;
    parameter CFG_BUSY_PACKED_LSB = SEED_CMD_DONE_PACKED_MSB + 1;
    parameter CFG_BUSY_PACKED_MSB = CFG_BUSY_PACKED_LSB + CFG_BUSY_WIDTH - 1;

    // Error status reg; active errors occupy bits [18:0], bits [31:19] are reserved.
    parameter logic [15:0] A_ERROR_STATUS = 16'h000C;
    parameter ADDR_ERR_WIDTH = 1;
    parameter ADDR_ERR_LSB = 0;
    parameter ADDR_ERR_MSB = ADDR_ERR_LSB + ADDR_ERR_WIDTH - 1;
    parameter WR_TO_RO_WIDTH = 1;
    parameter WR_TO_RO_LSB = 1;
    parameter WR_TO_RO_MSB = WR_TO_RO_LSB + WR_TO_RO_WIDTH - 1;
    parameter RD_TO_WO_WIDTH = 1;
    parameter RD_TO_WO_LSB = 2;
    parameter RD_TO_WO_MSB = RD_TO_WO_LSB + RD_TO_WO_WIDTH - 1;
    parameter NODE_CFG_WHILE_RUN_WIDTH = 1;
    parameter NODE_CFG_WHILE_RUN_LSB = 3;
    parameter NODE_CFG_WHILE_RUN_MSB = NODE_CFG_WHILE_RUN_LSB + NODE_CFG_WHILE_RUN_WIDTH - 1;
    parameter EDGE_CFG_WHILE_RUN_WIDTH = 1;
    parameter EDGE_CFG_WHILE_RUN_LSB = 4;
    parameter EDGE_CFG_WHILE_RUN_MSB = EDGE_CFG_WHILE_RUN_LSB + EDGE_CFG_WHILE_RUN_WIDTH - 1;
    parameter RUN_WITHOUT_CFG_DONE_WIDTH = 1;
    parameter RUN_WITHOUT_CFG_DONE_LSB = 5;
    parameter RUN_WITHOUT_CFG_DONE_MSB = RUN_WITHOUT_CFG_DONE_LSB + RUN_WITHOUT_CFG_DONE_WIDTH - 1;
    parameter RUN_WHEN_BUSY_WIDTH = 1;
    parameter RUN_WHEN_BUSY_LSB = 6;
    parameter RUN_WHEN_BUSY_MSB = RUN_WHEN_BUSY_LSB + RUN_WHEN_BUSY_WIDTH - 1;
    parameter UNIT_ROW_OOR_WIDTH = 1;
    parameter UNIT_ROW_OOR_LSB = 7;
    parameter UNIT_ROW_OOR_MSB = UNIT_ROW_OOR_LSB + UNIT_ROW_OOR_WIDTH - 1;
    parameter UNIT_COL_OOR_WIDTH = 1;
    parameter UNIT_COL_OOR_LSB = 8;
    parameter UNIT_COL_OOR_MSB = UNIT_COL_OOR_LSB + UNIT_COL_OOR_WIDTH - 1;
    parameter EDGE_BOUNDARY_ERR_WIDTH = 1;
    parameter EDGE_BOUNDARY_ERR_LSB = 9;
    parameter EDGE_BOUNDARY_ERR_MSB = EDGE_BOUNDARY_ERR_LSB + EDGE_BOUNDARY_ERR_WIDTH - 1;
    parameter EDGE_TYPE_ERR_WIDTH = 1;
    parameter EDGE_TYPE_ERR_LSB = 10;
    parameter EDGE_TYPE_ERR_MSB = EDGE_TYPE_ERR_LSB + EDGE_TYPE_ERR_WIDTH - 1;
    parameter UART_FRAME_ERR_WIDTH = 1;
    parameter UART_FRAME_ERR_LSB = 11;
    parameter UART_FRAME_ERR_MSB = UART_FRAME_ERR_LSB + UART_FRAME_ERR_WIDTH - 1;
    parameter UART_OVERFLOW_WIDTH = 1;
    parameter UART_OVERFLOW_LSB = 12;
    parameter UART_OVERFLOW_MSB = UART_OVERFLOW_LSB + UART_OVERFLOW_WIDTH - 1;
    parameter SNAP_ADDR_OOR_WIDTH = 1;
    parameter SNAP_ADDR_OOR_LSB = 13;
    parameter SNAP_ADDR_OOR_MSB = SNAP_ADDR_OOR_LSB + SNAP_ADDR_OOR_WIDTH - 1;

    parameter SEED_CFG_WHILE_RUN_WIDTH = 1;
    parameter SEED_CFG_WHILE_RUN_LSB = 14;
    parameter SEED_CFG_WHILE_RUN_MSB = SEED_CFG_WHILE_RUN_LSB + SEED_CFG_WHILE_RUN_WIDTH - 1;
    parameter I0_CFG_WHILE_RUN_WIDTH = 1;
    parameter I0_CFG_WHILE_RUN_LSB = 15;
    parameter I0_CFG_WHILE_RUN_MSB = I0_CFG_WHILE_RUN_LSB + I0_CFG_WHILE_RUN_WIDTH - 1;
    parameter SWEEP_CFG_WHILE_RUN_WIDTH = 1;
    parameter SWEEP_CFG_WHILE_RUN_LSB = 16;
    parameter SWEEP_CFG_WHILE_RUN_MSB = SWEEP_CFG_WHILE_RUN_LSB + SWEEP_CFG_WHILE_RUN_WIDTH - 1;
    parameter CFG_CMD_WHILE_BUSY_WIDTH = 1;
    parameter CFG_CMD_WHILE_BUSY_LSB = 17;
    parameter CFG_CMD_WHILE_BUSY_MSB = CFG_CMD_WHILE_BUSY_LSB + CFG_CMD_WHILE_BUSY_WIDTH - 1;
    parameter RUN_WHILE_CFG_BUSY_WIDTH = 1;
    parameter RUN_WHILE_CFG_BUSY_LSB = 18;
    parameter RUN_WHILE_CFG_BUSY_MSB = RUN_WHILE_CFG_BUSY_LSB + RUN_WHILE_CFG_BUSY_WIDTH - 1;

    parameter GLOBAL_CFG_WHILE_RUN_WIDTH = 1;
    parameter GLOBAL_CFG_WHILE_RUN_LSB = 19;
    parameter GLOBAL_CFG_WHILE_RUN_MSB = GLOBAL_CFG_WHILE_RUN_LSB + GLOBAL_CFG_WHILE_RUN_WIDTH - 1;

    parameter ERROR_STATUS_PACKED_WIDTH = ADDR_ERR_WIDTH + WR_TO_RO_WIDTH + RD_TO_WO_WIDTH + NODE_CFG_WHILE_RUN_WIDTH + EDGE_CFG_WHILE_RUN_WIDTH + RUN_WITHOUT_CFG_DONE_WIDTH + RUN_WHEN_BUSY_WIDTH + UNIT_ROW_OOR_WIDTH + UNIT_COL_OOR_WIDTH + EDGE_BOUNDARY_ERR_WIDTH + EDGE_TYPE_ERR_WIDTH + UART_FRAME_ERR_WIDTH + UART_OVERFLOW_WIDTH + SNAP_ADDR_OOR_WIDTH + SEED_CFG_WHILE_RUN_WIDTH + I0_CFG_WHILE_RUN_WIDTH + SWEEP_CFG_WHILE_RUN_WIDTH + CFG_CMD_WHILE_BUSY_WIDTH + RUN_WHILE_CFG_BUSY_WIDTH + GLOBAL_CFG_WHILE_RUN_WIDTH;
    parameter ADDR_ERR_PACKED_LSB = 0;
    parameter ADDR_ERR_PACKED_MSB = ADDR_ERR_PACKED_LSB + ADDR_ERR_WIDTH - 1;
    parameter WR_TO_RO_PACKED_LSB = ADDR_ERR_PACKED_MSB + 1;
    parameter WR_TO_RO_PACKED_MSB = WR_TO_RO_PACKED_LSB + WR_TO_RO_WIDTH - 1;
    parameter RD_TO_WO_PACKED_LSB = WR_TO_RO_PACKED_MSB + 1;
    parameter RD_TO_WO_PACKED_MSB = RD_TO_WO_PACKED_LSB + RD_TO_WO_WIDTH - 1;
    parameter NODE_CFG_WHILE_RUN_PACKED_LSB = RD_TO_WO_PACKED_MSB + 1;
    parameter NODE_CFG_WHILE_RUN_PACKED_MSB = NODE_CFG_WHILE_RUN_PACKED_LSB + NODE_CFG_WHILE_RUN_WIDTH - 1;
    parameter EDGE_CFG_WHILE_RUN_PACKED_LSB = NODE_CFG_WHILE_RUN_PACKED_MSB + 1;
    parameter EDGE_CFG_WHILE_RUN_PACKED_MSB = EDGE_CFG_WHILE_RUN_PACKED_LSB + EDGE_CFG_WHILE_RUN_WIDTH - 1;
    parameter RUN_WITHOUT_CFG_DONE_PACKED_LSB = EDGE_CFG_WHILE_RUN_PACKED_MSB + 1;
    parameter RUN_WITHOUT_CFG_DONE_PACKED_MSB = RUN_WITHOUT_CFG_DONE_PACKED_LSB + RUN_WITHOUT_CFG_DONE_WIDTH - 1;
    parameter RUN_WHEN_BUSY_PACKED_LSB = RUN_WITHOUT_CFG_DONE_PACKED_MSB + 1;
    parameter RUN_WHEN_BUSY_PACKED_MSB = RUN_WHEN_BUSY_PACKED_LSB + RUN_WHEN_BUSY_WIDTH - 1;
    parameter UNIT_ROW_OOR_PACKED_LSB = RUN_WHEN_BUSY_PACKED_MSB + 1;
    parameter UNIT_ROW_OOR_PACKED_MSB = UNIT_ROW_OOR_PACKED_LSB + UNIT_ROW_OOR_WIDTH - 1;
    parameter UNIT_COL_OOR_PACKED_LSB = UNIT_ROW_OOR_PACKED_MSB + 1;
    parameter UNIT_COL_OOR_PACKED_MSB = UNIT_COL_OOR_PACKED_LSB + UNIT_COL_OOR_WIDTH - 1;
    parameter EDGE_BOUNDARY_ERR_PACKED_LSB = UNIT_COL_OOR_PACKED_MSB + 1;
    parameter EDGE_BOUNDARY_ERR_PACKED_MSB = EDGE_BOUNDARY_ERR_PACKED_LSB + EDGE_BOUNDARY_ERR_WIDTH - 1;
    parameter EDGE_TYPE_ERR_PACKED_LSB = EDGE_BOUNDARY_ERR_PACKED_MSB + 1;
    parameter EDGE_TYPE_ERR_PACKED_MSB = EDGE_TYPE_ERR_PACKED_LSB + EDGE_TYPE_ERR_WIDTH - 1;
    parameter UART_FRAME_ERR_PACKED_LSB = EDGE_TYPE_ERR_PACKED_MSB + 1;
    parameter UART_FRAME_ERR_PACKED_MSB = UART_FRAME_ERR_PACKED_LSB + UART_FRAME_ERR_WIDTH - 1;
    parameter UART_OVERFLOW_PACKED_LSB = UART_FRAME_ERR_PACKED_MSB + 1;
    parameter UART_OVERFLOW_PACKED_MSB = UART_OVERFLOW_PACKED_LSB + UART_OVERFLOW_WIDTH - 1;
    parameter SNAP_ADDR_OOR_PACKED_LSB = UART_OVERFLOW_PACKED_MSB + 1;
    parameter SNAP_ADDR_OOR_PACKED_MSB = SNAP_ADDR_OOR_PACKED_LSB + SNAP_ADDR_OOR_WIDTH - 1;
    parameter SEED_CFG_WHILE_RUN_PACKED_LSB = SNAP_ADDR_OOR_PACKED_MSB + 1;
    parameter SEED_CFG_WHILE_RUN_PACKED_MSB = SEED_CFG_WHILE_RUN_PACKED_LSB + SEED_CFG_WHILE_RUN_WIDTH - 1;
    parameter I0_CFG_WHILE_RUN_PACKED_LSB = SEED_CFG_WHILE_RUN_PACKED_MSB + 1;
    parameter I0_CFG_WHILE_RUN_PACKED_MSB = I0_CFG_WHILE_RUN_PACKED_LSB + I0_CFG_WHILE_RUN_WIDTH - 1;
    parameter SWEEP_CFG_WHILE_RUN_PACKED_LSB = I0_CFG_WHILE_RUN_PACKED_MSB + 1;
    parameter SWEEP_CFG_WHILE_RUN_PACKED_MSB = SWEEP_CFG_WHILE_RUN_PACKED_LSB + SWEEP_CFG_WHILE_RUN_WIDTH - 1;
    parameter CFG_CMD_WHILE_BUSY_PACKED_LSB = SWEEP_CFG_WHILE_RUN_PACKED_MSB + 1;
    parameter CFG_CMD_WHILE_BUSY_PACKED_MSB = CFG_CMD_WHILE_BUSY_PACKED_LSB + CFG_CMD_WHILE_BUSY_WIDTH - 1;
    parameter RUN_WHILE_CFG_BUSY_PACKED_LSB = CFG_CMD_WHILE_BUSY_PACKED_MSB + 1;
    parameter RUN_WHILE_CFG_BUSY_PACKED_MSB = RUN_WHILE_CFG_BUSY_PACKED_LSB + RUN_WHILE_CFG_BUSY_WIDTH - 1;

    parameter GLOBAL_CFG_WHILE_RUN_PACKED_LSB = RUN_WHILE_CFG_BUSY_PACKED_MSB + 1;
    parameter GLOBAL_CFG_WHILE_RUN_PACKED_MSB = GLOBAL_CFG_WHILE_RUN_PACKED_LSB + GLOBAL_CFG_WHILE_RUN_WIDTH - 1;

    // Node rdata cfg reg
    parameter logic [15:0] A_NODE_RDATA_CFG = 16'h0084;
    parameter NODE_RDATA_CFG_INIT_SPIN_WIDTH = 1;
    parameter NODE_RDATA_CFG_INIT_SPIN_LSB = 0;
    parameter NODE_RDATA_CFG_INIT_SPIN_MSB = NODE_RDATA_CFG_INIT_SPIN_LSB + NODE_RDATA_CFG_INIT_SPIN_WIDTH - 1;
    parameter NODE_RDATA_CFG_CLAMP_EN_WIDTH = 1;
    parameter NODE_RDATA_CFG_CLAMP_EN_LSB = 1;
    parameter NODE_RDATA_CFG_CLAMP_EN_MSB = NODE_RDATA_CFG_CLAMP_EN_LSB + NODE_RDATA_CFG_CLAMP_EN_WIDTH - 1;
    parameter NODE_RDATA_CFG_CLAMP_SPIN_WIDTH = 1;
    parameter NODE_RDATA_CFG_CLAMP_SPIN_LSB = 2;
    parameter NODE_RDATA_CFG_CLAMP_SPIN_MSB = NODE_RDATA_CFG_CLAMP_SPIN_LSB + NODE_RDATA_CFG_CLAMP_SPIN_WIDTH - 1;
    parameter NODE_RDATA_CFG_BIAS_SIGN_WIDTH = 1;
    parameter NODE_RDATA_CFG_BIAS_SIGN_LSB = 3;
    parameter NODE_RDATA_CFG_BIAS_SIGN_MSB = NODE_RDATA_CFG_BIAS_SIGN_LSB + NODE_RDATA_CFG_BIAS_SIGN_WIDTH - 1;
    parameter NODE_RDATA_CFG_BIAS_PROB_WIDTH = 7;
    parameter NODE_RDATA_CFG_BIAS_PROB_LSB = 4;
    parameter NODE_RDATA_CFG_BIAS_PROB_MSB = NODE_RDATA_CFG_BIAS_PROB_LSB + NODE_RDATA_CFG_BIAS_PROB_WIDTH - 1;

    parameter NODE_RDATA_CFG_PACKED_WIDTH = NODE_RDATA_CFG_INIT_SPIN_WIDTH + NODE_RDATA_CFG_CLAMP_EN_WIDTH + NODE_RDATA_CFG_CLAMP_SPIN_WIDTH + NODE_RDATA_CFG_BIAS_SIGN_WIDTH + NODE_RDATA_CFG_BIAS_PROB_WIDTH;
    parameter NODE_RDATA_CFG_INIT_SPIN_PACKED_LSB = 0;
    parameter NODE_RDATA_CFG_INIT_SPIN_PACKED_MSB = NODE_RDATA_CFG_INIT_SPIN_PACKED_LSB + NODE_RDATA_CFG_INIT_SPIN_WIDTH - 1;
    parameter NODE_RDATA_CFG_CLAMP_EN_PACKED_LSB = NODE_RDATA_CFG_INIT_SPIN_PACKED_MSB + 1;
    parameter NODE_RDATA_CFG_CLAMP_EN_PACKED_MSB = NODE_RDATA_CFG_CLAMP_EN_PACKED_LSB + NODE_RDATA_CFG_CLAMP_EN_WIDTH - 1;
    parameter NODE_RDATA_CFG_CLAMP_SPIN_PACKED_LSB = NODE_RDATA_CFG_CLAMP_EN_PACKED_MSB + 1;
    parameter NODE_RDATA_CFG_CLAMP_SPIN_PACKED_MSB = NODE_RDATA_CFG_CLAMP_SPIN_PACKED_LSB + NODE_RDATA_CFG_CLAMP_SPIN_WIDTH - 1;
    parameter NODE_RDATA_CFG_BIAS_SIGN_PACKED_LSB = NODE_RDATA_CFG_CLAMP_SPIN_PACKED_MSB + 1;
    parameter NODE_RDATA_CFG_BIAS_SIGN_PACKED_MSB = NODE_RDATA_CFG_BIAS_SIGN_PACKED_LSB + NODE_RDATA_CFG_BIAS_SIGN_WIDTH - 1;
    parameter NODE_RDATA_CFG_BIAS_PROB_PACKED_LSB = NODE_RDATA_CFG_BIAS_SIGN_PACKED_MSB + 1;
    parameter NODE_RDATA_CFG_BIAS_PROB_PACKED_MSB = NODE_RDATA_CFG_BIAS_PROB_PACKED_LSB + NODE_RDATA_CFG_BIAS_PROB_WIDTH - 1;

    // Seed rdata reg
    parameter logic [15:0] A_SEED_RDATA = 16'h0094;
    parameter SEED_RDATA_WIDTH = 32;
    parameter SEED_RDATA_LSB = 0;
    parameter SEED_RDATA_MSB = SEED_RDATA_LSB + SEED_RDATA_WIDTH - 1;

    parameter SEED_RDATA_PACKED_WIDTH = SEED_RDATA_WIDTH;
    parameter SEED_RDATA_PACKED_LSB = 0;
    parameter SEED_RDATA_PACKED_MSB = SEED_RDATA_PACKED_LSB + SEED_RDATA_WIDTH - 1;

    // Edge rdata reg
    parameter logic [15:0] A_EDGE_RDATA = 16'h00A4;
    parameter EDGE_RDATA_EDGE_VALID_WIDTH = 1;
    parameter EDGE_RDATA_EDGE_VALID_LSB = 0;
    parameter EDGE_RDATA_EDGE_VALID_MSB = EDGE_RDATA_EDGE_VALID_LSB + EDGE_RDATA_EDGE_VALID_WIDTH - 1;
    parameter EDGE_RDATA_EDGE_SIGN_WIDTH = 1;
    parameter EDGE_RDATA_EDGE_SIGN_LSB = 1;
    parameter EDGE_RDATA_EDGE_SIGN_MSB = EDGE_RDATA_EDGE_SIGN_LSB + EDGE_RDATA_EDGE_SIGN_WIDTH - 1;
    parameter EDGE_RDATA_EDGE_PROB_WIDTH = 7;
    parameter EDGE_RDATA_EDGE_PROB_LSB = 2;
    parameter EDGE_RDATA_EDGE_PROB_MSB = EDGE_RDATA_EDGE_PROB_LSB + EDGE_RDATA_EDGE_PROB_WIDTH - 1;

    parameter EDGE_RDATA_PACKED_WIDTH = EDGE_RDATA_EDGE_VALID_WIDTH + EDGE_RDATA_EDGE_SIGN_WIDTH + EDGE_RDATA_EDGE_PROB_WIDTH;
    parameter EDGE_RDATA_EDGE_VALID_PACKED_LSB = 0;
    parameter EDGE_RDATA_EDGE_VALID_PACKED_MSB = EDGE_RDATA_EDGE_VALID_PACKED_LSB + EDGE_RDATA_EDGE_VALID_WIDTH - 1;
    parameter EDGE_RDATA_EDGE_SIGN_PACKED_LSB = EDGE_RDATA_EDGE_VALID_PACKED_MSB + 1;
    parameter EDGE_RDATA_EDGE_SIGN_PACKED_MSB = EDGE_RDATA_EDGE_SIGN_PACKED_LSB + EDGE_RDATA_EDGE_SIGN_WIDTH - 1;
    parameter EDGE_RDATA_EDGE_PROB_PACKED_LSB = EDGE_RDATA_EDGE_SIGN_PACKED_MSB + 1;
    parameter EDGE_RDATA_EDGE_PROB_PACKED_MSB = EDGE_RDATA_EDGE_PROB_PACKED_LSB + EDGE_RDATA_EDGE_PROB_WIDTH - 1;

 // Spin data0 reg
    parameter logic [15:0] A_SPIN_RDATA0 = 16'h00A8;
    parameter SPIN_RDATA_DATA_WIDTH = 32;
    parameter SPIN_RDATA_DATA_LSB = 0;
    parameter SPIN_RDATA_DATA_MSB = SPIN_RDATA_DATA_LSB + SPIN_RDATA_DATA_WIDTH - 1;

    parameter SPIN_RDATA_PACKED_WIDTH = SPIN_RDATA_DATA_WIDTH;
    parameter SPIN_RDATA_DATA_PACKED_LSB = 0;
    parameter SPIN_RDATA_DATA_PACKED_MSB = SPIN_RDATA_DATA_PACKED_LSB + SPIN_RDATA_DATA_WIDTH - 1;

    // Spin data1 reg
    parameter logic [15:0] A_SPIN_RDATA1 = 16'h00AC;

    // Spin data2 reg
    parameter logic [15:0] A_SPIN_RDATA2 = 16'h00B0;

    // Spin data3 reg
    parameter logic [15:0] A_SPIN_RDATA3 = 16'h00B4;

    // Spin data4 reg
    parameter logic [15:0] A_SPIN_RDATA4 = 16'h00B8;

    // Spin data5 reg
    parameter logic [15:0] A_SPIN_RDATA5 = 16'h00BC;

    // Spin data6 reg
    parameter logic [15:0] A_SPIN_RDATA6 = 16'h00C0;

    // Spin data7 reg
    parameter logic [15:0] A_SPIN_RDATA7 = 16'h00C4;

    // Spin data8 reg
    parameter logic [15:0] A_SPIN_RDATA8 = 16'h00C8;

    // Spin data9 reg
    parameter logic [15:0] A_SPIN_RDATA9 = 16'h00CC;
    // Configuration transport: one outstanding request for the entire array.
    // pbit_reg_block checks staged configuration and current status at CMD acceptance.
    // Only legal commands issue requests; lock their payload until completion.
    // Invalid commands set local error status, issue no request, and do not set CFG_BUSY.
    // Locally completed invalid commands set CMD_DONE and zero RDATA if readback is requested.
    // Commands rejected while CFG_BUSY only set error status; preserve the in-flight command.
    // CMD_DONE means processing finished, not success. Read GLOBAL_STATUS clears CMD_DONE;
    // a simultaneous completion takes priority over the read-clear.
    // valid && ready accepts a request; hold request data stable until acceptance.
    // Responses are always accepted; valid is separate from the packed payload.
    // Reset discards all pending valid bits. RUN_START waits until CFG_BUSY=0.
    parameter int BANK_LOCAL_ROW_WIDTH = (BANK_TILE_ROWS > 1) ? $clog2(BANK_TILE_ROWS) : 1;
    parameter int BANK_LOCAL_COL_WIDTH = (BANK_TILE_COLS > 1) ? $clog2(BANK_TILE_COLS) : 1;
    parameter int CFG_OBJECT_WIDTH = EDGE_TYPE_WIDTH + EDGE_TARGET_NUMBER_WIDTH;
    parameter int CFG_DATA_WIDTH = 32;

    typedef enum logic [1:0] {
        CFG_TARGET_NODE = 2'd0,
        CFG_TARGET_SEED = 2'd1,
        CFG_TARGET_EDGE = 2'd2
    } cfg_target_e;

    // object_idx: NODE={2'b00,col,row}, SEED={3'b000,number}, EDGE={type,number}.
    // wdata: zero-extended NODE_CFG/EDGE_CFG packed fields, or the complete seed.
    // readback/clear/apply are independent flags, not software CMD bit positions.
    // clear is legal only for EDGE; retain existing CLEAR/APPLY edge semantics.
    typedef struct packed {
        cfg_target_e target;
        logic [CFG_OBJECT_WIDTH-1:0] object_idx;
        logic readback;
        logic clear;
        logic apply;
        logic [CFG_DATA_WIDTH-1:0] wdata;
    } cfg_payload_t;

    typedef struct packed {
        logic [UNIT_TARGET_ROW_WIDTH-1:0] unit_row;
        logic [UNIT_TARGET_COL_WIDTH-1:0] unit_col;
        cfg_payload_t payload;
    } cfg_array_req_t;

    // Array decodes BANK selection separately; only local coordinates reach a BANK.
    typedef struct packed {
        logic [BANK_LOCAL_ROW_WIDTH-1:0] cell_row;
        logic [BANK_LOCAL_COL_WIDTH-1:0] cell_col;
        cfg_payload_t payload;
    } cfg_bank_req_t;

    // Only legal requests enter the array/BANK configuration path.
    // Capture readback after writes take effect; responses without readback carry zero rdata.
    // Response valid reports completion; errors are reported locally by pbit_reg_block.
    // The request owner retains target/readback metadata until response completion.
    typedef struct packed {
        logic [CFG_DATA_WIDTH-1:0] rdata;
    } cfg_rsp_t;

    localparam int CFG_PAYLOAD_WIDTH = $bits(cfg_payload_t);
    localparam int CFG_ARRAY_REQ_WIDTH = $bits(cfg_array_req_t);
    localparam int CFG_BANK_REQ_WIDTH = $bits(cfg_bank_req_t);
    localparam int CFG_RSP_WIDTH = $bits(cfg_rsp_t);

endpackage
`endif
