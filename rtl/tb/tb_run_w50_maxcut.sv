`ifndef TB_RUN_W50_MAXCUT
`define TB_RUN_W50_MAXCUT
import pbit_pkg::*;

module tb;
    localparam int unsigned CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;
    localparam int unsigned UART_BIT_TIME_NS = 1_000_000_000 / BAUD_RATE;
    localparam int unsigned W50_SNAPSHOT_PAGES = 3;
    localparam int unsigned W50_MIN_RUN_POLL_LIMIT = 1200;

    localparam logic [7:0] OP_WRITE = 8'h01;
    localparam logic [7:0] OP_READ  = 8'h02;

    typedef enum logic [7:0] {
        ST_OK       = 8'h00,
        ST_BAD      = 8'h01,
        ST_REG_ERR  = 8'h02,
        ST_BUSY     = 8'h03
    } status_e;

    logic clk;
    logic rst_n;
    logic uart_rx_i;
    logic uart_tx_o;
    int unsigned error_count;
    logic [31:0] snapshot_words [W50_SNAPSHOT_PAGES][SPIN_RDATA_REG_NUM];

    pbit_top u_pbit_top (
        .clk       (clk),
        .rst_n     (rst_n),
        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o)
    );

    `include "tb_w50_maxcut_data.svh"

    localparam int unsigned W50_PROGRESS_PRINT_STEP = 500;

    int unsigned live_cut_history [W50_NUM_SWEEPS];
    int unsigned live_best_cut_history [W50_NUM_SWEEPS];
    int unsigned live_broken_chain_history [W50_NUM_SWEEPS];
    int unsigned live_sample_count;
    int unsigned live_best_cut;
    int unsigned live_best_sweep;
    int unsigned live_best_cycle;
    int unsigned live_best_broken_chains;
    int unsigned live_final_cut;
    int unsigned live_final_cycle;
    int unsigned live_final_broken_chains;
    integer live_history_fd;

    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    function automatic logic [15:0] reg_addr_stride4(
        input logic [15:0] base,
        input int unsigned idx
    );
        logic [15:0] offset;
        begin
            offset = idx * 4;
            reg_addr_stride4 = base + offset;
        end
    endfunction

    function automatic logic [15:0] spin_rdata_addr(input int unsigned idx);
        case (idx)
            0: spin_rdata_addr = A_SPIN_RDATA0;
            1: spin_rdata_addr = A_SPIN_RDATA1;
            2: spin_rdata_addr = A_SPIN_RDATA2;
            3: spin_rdata_addr = A_SPIN_RDATA3;
            4: spin_rdata_addr = A_SPIN_RDATA4;
            5: spin_rdata_addr = A_SPIN_RDATA5;
            6: spin_rdata_addr = A_SPIN_RDATA6;
            7: spin_rdata_addr = A_SPIN_RDATA7;
            8: spin_rdata_addr = A_SPIN_RDATA8;
            default: spin_rdata_addr = A_SPIN_RDATA9;
        endcase
    endfunction

    function automatic logic [31:0] pack_global_cfg(
        input logic [NUM_SWEEP_WIDTH-1:0] num_sweeps_actual,
        input logic [NUM_MAJORITY_WIDTH-1:0] num_majority_actual
    );
        pack_global_cfg = '0;
        pack_global_cfg[NUM_SWEEP_MSB:NUM_SWEEP_LSB] = NUM_SWEEP_WIDTH'(num_sweeps_actual - 1);
        pack_global_cfg[NUM_MAJORITY_MSB:NUM_MAJORITY_LSB] = NUM_MAJORITY_WIDTH'(num_majority_actual - 1);
    endfunction

    function automatic logic [31:0] pack_global_ctrl(
        input logic soft_reset,
        input logic cfg_done_set,
        input logic cfg_done_clear,
        input logic run_start,
        input logic snapshot_latch,
        input logic run_done_clear,
        input logic error_clear
    );
        pack_global_ctrl = '0;
        pack_global_ctrl[SOFT_RESET_MSB:SOFT_RESET_LSB] = soft_reset;
        pack_global_ctrl[CFG_DONE_SET_MSB:CFG_DONE_SET_LSB] = cfg_done_set;
        pack_global_ctrl[CFG_DONE_CLEAR_MSB:CFG_DONE_CLEAR_LSB] = cfg_done_clear;
        pack_global_ctrl[RUN_START_MSB:RUN_START_LSB] = run_start;
        pack_global_ctrl[SNAPSHOT_LATCH_MSB:SNAPSHOT_LATCH_LSB] = snapshot_latch;
        pack_global_ctrl[RUN_DONE_CLEAR_MSB:RUN_DONE_CLEAR_LSB] = run_done_clear;
        pack_global_ctrl[ERROR_CLEAR_MSB:ERROR_CLEAR_LSB] = error_clear;
    endfunction

    function automatic logic [31:0] pack_node_target(
        input logic [TARGET_MODE_WIDTH-1:0]     mode,
        input logic [NODE_TARGET_ROW_WIDTH-1:0] row,
        input logic [NODE_TARGET_COL_WIDTH-1:0] col
    );
        pack_node_target = '0;
        pack_node_target[TARGET_MODE_MSB:TARGET_MODE_LSB] = mode;
        pack_node_target[NODE_TARGET_ROW_MSB:NODE_TARGET_ROW_LSB] = row;
        pack_node_target[NODE_TARGET_COL_MSB:NODE_TARGET_COL_LSB] = col;
    endfunction

    function automatic logic [31:0] pack_node_cfg(
        input logic init_spin,
        input logic clamp_en,
        input logic clamp_spin
    );
        pack_node_cfg = '0;
        pack_node_cfg[INIT_VALID_MSB:INIT_VALID_LSB] = 1'b1;
        pack_node_cfg[CLAMP_VALID_MSB:CLAMP_VALID_LSB] = 1'b1;
        pack_node_cfg[BIAS_VALID_MSB:BIAS_VALID_LSB] = 1'b1;
        pack_node_cfg[NODE_CFG_INIT_SPIN_MSB:NODE_CFG_INIT_SPIN_LSB] = init_spin;
        pack_node_cfg[NODE_CFG_CLAMP_EN_MSB:NODE_CFG_CLAMP_EN_LSB] = clamp_en;
        pack_node_cfg[NODE_CFG_CLAMP_SPIN_MSB:NODE_CFG_CLAMP_SPIN_LSB] = clamp_spin;
        pack_node_cfg[NODE_CFG_BIAS_SIGN_MSB:NODE_CFG_BIAS_SIGN_LSB] = 1'b1;
        pack_node_cfg[NODE_CFG_BIAS_PROB_MSB:NODE_CFG_BIAS_PROB_LSB] = '0;
    endfunction

    function automatic logic [31:0] pack_node_cmd(
        input logic apply_cfg,
        input logic apply_seed,
        input logic load_node,
        input logic clear_cfg_scope_en,
        input logic clear_seed_scope_en,
        input logic clear_local_all,
        input logic readback_cfg,
        input logic readback_seed
    );
        pack_node_cmd = '0;
        pack_node_cmd[APPLY_CFG_MSB:APPLY_CFG_LSB] = apply_cfg;
        pack_node_cmd[APPLY_SEED_MSB:APPLY_SEED_LSB] = apply_seed;
        pack_node_cmd[LOAD_NODE_MSB:LOAD_NODE_LSB] = load_node;
        pack_node_cmd[CLEAR_CFG_SCOPE_EN_MSB:CLEAR_CFG_SCOPE_EN_LSB] = clear_cfg_scope_en;
        pack_node_cmd[CLEAR_SEED_SCOPE_EN_MSB:CLEAR_SEED_SCOPE_EN_LSB] = clear_seed_scope_en;
        pack_node_cmd[CLEAR_LOCAL_ALL_MSB:CLEAR_LOCAL_ALL_LSB] = clear_local_all;
        pack_node_cmd[READBACK_CFG_MSB:READBACK_CFG_LSB] = readback_cfg;
        pack_node_cmd[READBACK_SEED_MSB:READBACK_SEED_LSB] = readback_seed;
    endfunction

    function automatic logic [31:0] pack_edge_target(
        input logic [EDGE_TYPE_WIDTH-1:0]       edge_type,
        input logic [EDGE_TARGET_ROW_WIDTH-1:0] row,
        input logic [EDGE_TARGET_COL_WIDTH-1:0] col
    );
        pack_edge_target = '0;
        pack_edge_target[EDGE_TYPE_MSB:EDGE_TYPE_LSB] = edge_type;
        pack_edge_target[EDGE_TARGET_ROW_MSB:EDGE_TARGET_ROW_LSB] = row;
        pack_edge_target[EDGE_TARGET_COL_MSB:EDGE_TARGET_COL_LSB] = col;
    endfunction

    function automatic logic [31:0] pack_edge_cfg(
        input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] prob,
        input logic sign,
        input logic valid
    );
        pack_edge_cfg = '0;
        pack_edge_cfg[EDGE_CFG_EDGE_VALID_MSB:EDGE_CFG_EDGE_VALID_LSB] = valid;
        pack_edge_cfg[EDGE_CFG_EDGE_SIGN_MSB:EDGE_CFG_EDGE_SIGN_LSB] = sign;
        pack_edge_cfg[EDGE_CFG_EDGE_PROB_MSB:EDGE_CFG_EDGE_PROB_LSB] = prob;
    endfunction

    function automatic logic [31:0] pack_edge_cmd(
        input logic apply_edge,
        input logic clear_edge,
        input logic readback_edge
    );
        pack_edge_cmd = '0;
        pack_edge_cmd[APPLY_EDGE_MSB:APPLY_EDGE_LSB] = apply_edge;
        pack_edge_cmd[CLEAR_EDGE_MSB:CLEAR_EDGE_LSB] = clear_edge;
        pack_edge_cmd[READBACK_EDGE_MSB:READBACK_EDGE_LSB] = readback_edge;
    endfunction

    function automatic logic [31:0] pack_i0_word(input int unsigned base_idx);
        pack_i0_word = '0;
        pack_i0_word[I0_LEVEL0_MSB:I0_LEVEL0_LSB] = w50_i0_level[base_idx + 0];
        pack_i0_word[I0_LEVEL1_MSB:I0_LEVEL1_LSB] = w50_i0_level[base_idx + 1];
        pack_i0_word[I0_LEVEL2_MSB:I0_LEVEL2_LSB] = w50_i0_level[base_idx + 2];
        pack_i0_word[I0_LEVEL3_MSB:I0_LEVEL3_LSB] = w50_i0_level[base_idx + 3];
    endfunction

    function automatic logic [31:0] pack_interval_word(input int unsigned base_idx);
        pack_interval_word = '0;
        pack_interval_word[SWEEP_INTERVAL0_MSB:SWEEP_INTERVAL0_LSB] = SWEEP_INTERVAL_WIDTH'(w50_sweep_interval[base_idx + 0] - 1);
        pack_interval_word[SWEEP_INTERVAL1_MSB:SWEEP_INTERVAL1_LSB] = SWEEP_INTERVAL_WIDTH'(w50_sweep_interval[base_idx + 1] - 1);
    endfunction

    task automatic report_mismatch(
        input string tag,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected) begin
            error_count++;
            $error("[%s] actual=0x%08h expected=0x%08h time=%0t", tag, actual, expected, $time);
        end
    endtask

    task automatic expect_status_ok(input string tag, input status_e status);
        if (status !== ST_OK) begin
            error_count++;
            $error("[%s] status=0x%02h expected ST_OK time=%0t", tag, status, $time);
        end
    endtask

    task automatic uart_send_byte(input logic [7:0] tx_data);
        uart_rx_i = 1'b0;
        #(UART_BIT_TIME_NS);
        for (int idx = 0; idx < 8; idx++) begin
            uart_rx_i = tx_data[idx];
            #(UART_BIT_TIME_NS);
        end
        uart_rx_i = 1'b1;
        #(UART_BIT_TIME_NS);
    endtask

    task automatic uart_receive_byte(output logic [7:0] rx_data);
        @(negedge uart_tx_o);
        #(UART_BIT_TIME_NS / 2);
        if (uart_tx_o !== 1'b0) begin
            error_count++;
            $error("[UART_TX] invalid start bit at time %0t", $time);
        end
        for (int idx = 0; idx < 8; idx++) begin
            #(UART_BIT_TIME_NS);
            rx_data[idx] = uart_tx_o;
        end
        #(UART_BIT_TIME_NS);
        if (uart_tx_o !== 1'b1) begin
            error_count++;
            $error("[UART_TX] invalid stop bit at time %0t", $time);
        end
    endtask

    task automatic uart_req(
        input  logic [7:0]  op,
        input  logic [15:0] addr,
        input  logic [31:0] wdata,
        output status_e     status,
        output logic [15:0] raddr,
        output logic [31:0] rdata
    );
        logic [7:0] rx_data;
        uart_send_byte(op);
        uart_send_byte(addr[15:8]);
        uart_send_byte(addr[7:0]);
        uart_send_byte(wdata[31:24]);
        uart_send_byte(wdata[23:16]);
        uart_send_byte(wdata[15:8]);
        uart_send_byte(wdata[7:0]);

        for (int idx = 0; idx < 7; idx++) begin
            uart_receive_byte(rx_data);
            case (idx)
                0: status = status_e'(rx_data);
                1: raddr[15:8] = rx_data;
                2: raddr[7:0] = rx_data;
                3: rdata[31:24] = rx_data;
                4: rdata[23:16] = rx_data;
                5: rdata[15:8] = rx_data;
                6: rdata[7:0] = rx_data;
                default: begin end
            endcase
        end
        #(UART_BIT_TIME_NS);
    endtask

    task automatic write_reg(
        input logic [15:0] addr,
        input logic [31:0] data,
        input string tag
    );
        status_e status;
        logic [15:0] raddr;
        logic [31:0] rdata;
        uart_req(OP_WRITE, addr, data, status, raddr, rdata);
        expect_status_ok({tag, " write status"}, status);
        report_mismatch({tag, " write addr"}, {16'd0, raddr}, {16'd0, addr});
        report_mismatch({tag, " write rdata"}, rdata, 32'd0);
    endtask

    task automatic read_reg(
        input  logic [15:0] addr,
        output logic [31:0] data,
        input  string tag
    );
        status_e status;
        logic [15:0] raddr;
        uart_req(OP_READ, addr, 32'd0, status, raddr, data);
        expect_status_ok({tag, " read status"}, status);
        report_mismatch({tag, " read addr"}, {16'd0, raddr}, {16'd0, addr});
    endtask

    task automatic hard_reset();
        uart_rx_i = 1'b1;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);
    endtask

    task automatic configure_run_registers();
        logic [31:0] rdata;
        logic [31:0] expected_global_cfg;

        expected_global_cfg = pack_global_cfg(W50_NUM_SWEEPS, W50_NUM_MAJORITY);
        write_reg(A_GLOBAL_CFG, expected_global_cfg, "global cfg");

        for (int reg_idx = 0; reg_idx < (W50_NUM_I0_LEVELS / 4); reg_idx++) begin
            write_reg(reg_addr_stride4(A_I0_LEVEL0, reg_idx), pack_i0_word(reg_idx * 4), "i0 level");
        end

        for (int reg_idx = 0; reg_idx < (W50_NUM_I0_LEVELS / 2); reg_idx++) begin
            write_reg(reg_addr_stride4(A_SWEEP_INTERVAL0, reg_idx), pack_interval_word(reg_idx * 2), "sweep interval");
        end

        read_reg(A_GLOBAL_CFG, rdata, "global cfg readback");
        report_mismatch("global cfg readback", rdata, expected_global_cfg);
    endtask

    task automatic configure_nodes();
        //cfg
        bit tile_seeded [SHARED_ROWS][SHARED_COLS];
        int unsigned tile_row;
        int unsigned tile_col;
        int unsigned configured_count;

        for (int idx = 0; idx < W50_NUM_PHYSICAL; idx++) begin
            write_reg(A_NODE_TARGET,
                      pack_node_target(TARGET_MODE_LOCAL, w50_phys_row[idx], w50_phys_col[idx]),
                      "node target");
            write_reg(A_NODE_CFG,
                      pack_node_cfg(w50_node_init_spin[idx], 1'b0, w50_node_init_spin[idx]),
                      "node cfg");
            write_reg(A_NODE_CMD, pack_node_cmd(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), "node apply");
            repeat (1) @(posedge clk);
        end

        //seed
        configured_count = 0;

        for (int r = 0; r < SHARED_ROWS; r++) begin
            for (int c = 0; c < SHARED_COLS; c++) begin
                tile_seeded[r][c] = 1'b0;
            end
        end

        for (int idx = 0; idx < W50_NUM_PHYSICAL; idx++) begin
            tile_row = w50_phys_row[idx] / 2;
            tile_col = w50_phys_col[idx] / 2;

            if (!tile_seeded[tile_row][tile_col]) begin
                write_reg(
                    A_NODE_TARGET,
                    pack_node_target(
                        TARGET_MODE_LOCAL,
                        NODE_TARGET_ROW_WIDTH'(tile_row),
                        NODE_TARGET_COL_WIDTH'(tile_col)
                    ),
                    "seed target"
                );

                write_reg(
                    A_NODE_SEED,
                    w50_node_seed[idx],
                    "node seed"
                );

                write_reg(
                    A_NODE_CMD,
                    pack_node_cmd(
                        1'b0, // apply_cfg
                        1'b1, // apply_seed
                        1'b0, // load_node
                        1'b0, 1'b0, 1'b0, 1'b0, 1'b0
                    ),
                    "node apply seed"
                );

                tile_seeded[tile_row][tile_col] = 1'b1;
                configured_count++;
            end
        end
        
        write_reg(
            A_NODE_CMD,
            pack_node_cmd(
                1'b0,
                1'b0,
                1'b1, // LOAD_NODE
                1'b0, 1'b0, 1'b0, 1'b0, 1'b0
            ),
            "node load"
        );        
    endtask

    task automatic clear_edges();
        for (int idx = 0; idx < W50_NUM_CLEAR_EDGES; idx++) begin
            write_reg(A_EDGE_TARGET,
                      pack_edge_target(w50_clear_edge_type[idx], w50_clear_edge_row[idx], w50_clear_edge_col[idx]),
                      "edge clear target");
            write_reg(A_EDGE_CMD, pack_edge_cmd(1'b0, 1'b1, 1'b0), "edge clear");
            repeat (1) @(posedge clk);
        end
    endtask

    task automatic configure_edges();
        for (int idx = 0; idx < W50_NUM_CONFIG_EDGES; idx++) begin
            write_reg(A_EDGE_TARGET,
                      pack_edge_target(w50_edge_type[idx], w50_edge_row[idx], w50_edge_col[idx]),
                      "edge target");
            write_reg(A_EDGE_CFG,
                      pack_edge_cfg(w50_edge_prob[idx], w50_edge_sign[idx], 1'b1),
                      "edge cfg");
            write_reg(A_EDGE_CMD, pack_edge_cmd(1'b1, 1'b0, 1'b0), "edge apply");
            repeat (1) @(posedge clk);
        end
    endtask

    task automatic dump_run_debug(input logic [31:0] status);
        $display("[RUN_W50_MAXCUT_DEBUG] status=0x%08h time=%0t", status, $time);
        $display("[RUN_W50_MAXCUT_DEBUG] phase_state=%0d sweep_cnt=%0d round=%0d i0=%0d run_busy=%0b run_done=%0b",
                 u_pbit_top.u_phase_ctrl_4color.state_q,
                 u_pbit_top.u_phase_ctrl_4color.sweep_cnt_q,
                 u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q,
                 u_pbit_top.i0_level_w,
                 u_pbit_top.u_phase_ctrl_4color.run_busy_o,
                 u_pbit_top.u_phase_ctrl_4color.run_done_o);
    endtask

    function automatic logic physical_spin_live(input int unsigned phys_idx);
        int unsigned flat_idx;
        begin
            flat_idx = (w50_phys_row[phys_idx] * COLS) + w50_phys_col[phys_idx];
            physical_spin_live = u_pbit_top.u_pbit_array_kings.spin_flat[flat_idx];
        end
    endfunction

    function automatic logic physical_spin_snapshot(input int unsigned phys_idx);
        int unsigned flat_idx;
        int unsigned page;
        int unsigned page_bit;
        int unsigned word;
        int unsigned bit_idx;
        begin
            flat_idx = (w50_phys_row[phys_idx] * COLS) + w50_phys_col[phys_idx];
            page = flat_idx / SNAPSHOT_WIDTH;
            page_bit = flat_idx % SNAPSHOT_WIDTH;
            word = page_bit / 32;
            bit_idx = page_bit % 32;
            physical_spin_snapshot = snapshot_words[page][word][bit_idx];
        end
    endfunction

    task automatic score_spins(
        input  bit use_live_spins,
        input  bit print_spins,
        output int unsigned cut_value,
        output int unsigned broken_chain_count
    );
        logic logical_spin [W50_NUM_LOGICAL];
        logic phys_spin;
        int signed chain_sum;
        int signed chain_sum_abs;
        int unsigned chain_len;

        broken_chain_count = 0;
        for (int logical = 0; logical < W50_NUM_LOGICAL; logical++) begin
            chain_sum = 0;
            for (int p = w50_chain_start[logical]; p < w50_chain_start[logical + 1]; p++) begin
                phys_spin = use_live_spins ?
                            physical_spin_live(w50_chain_phys_idx[p]) :
                            physical_spin_snapshot(w50_chain_phys_idx[p]);
                chain_sum += phys_spin ? 1 : -1;
            end
            chain_len = w50_chain_start[logical + 1] - w50_chain_start[logical];
            chain_sum_abs = (chain_sum < 0) ? -chain_sum : chain_sum;
            if (chain_sum_abs != chain_len) begin
                broken_chain_count++;
            end
            logical_spin[logical] = (chain_sum >= 0);
        end

        cut_value = 0;
        for (int edge_idx = 0; edge_idx < W50_NUM_LOGICAL_EDGES; edge_idx++) begin
            if (logical_spin[w50_logical_edge_a[edge_idx]] != logical_spin[w50_logical_edge_b[edge_idx]]) begin
                cut_value += w50_logical_edge_weight[edge_idx];
            end
        end

        if (print_spins) begin
            $display("[RUN_W50_MAXCUT] logical spins:");
            for (int row = 0; row < 5; row++) begin
                $display("[RUN_W50_MAXCUT] spin[%0d:%0d]=%0b%0b%0b%0b%0b%0b%0b%0b%0b%0b",
                         row * 10, row * 10 + 9,
                         logical_spin[row * 10 + 0], logical_spin[row * 10 + 1],
                         logical_spin[row * 10 + 2], logical_spin[row * 10 + 3],
                         logical_spin[row * 10 + 4], logical_spin[row * 10 + 5],
                         logical_spin[row * 10 + 6], logical_spin[row * 10 + 7],
                         logical_spin[row * 10 + 8], logical_spin[row * 10 + 9]);
            end
            $display("[RUN_W50_MAXCUT] broken_chains=%0d/%0d", broken_chain_count, W50_NUM_LOGICAL);
        end
    endtask

    task automatic init_live_score_history();
        for (int sweep = 0; sweep < W50_NUM_SWEEPS; sweep++) begin
            live_cut_history[sweep] = 0;
            live_best_cut_history[sweep] = 0;
            live_broken_chain_history[sweep] = 0;
        end
        live_sample_count = 0;
        live_best_cut = 0;
        live_best_sweep = 0;
        live_best_cycle = 0;
        live_best_broken_chains = 0;
        live_final_cut = 0;
        live_final_cycle = 0;
        live_final_broken_chains = 0;
        live_history_fd = $fopen("sim_run_w50_cut_history.csv", "w");
        if (live_history_fd != 0) begin
            $fdisplay(live_history_fd, "sweep,cycles_since_run_start,current_cut,best_cut,best_sweep,best_cycle,broken_chains,best_broken_chains,i0_level,round,time");
        end else begin
            $display("[RUN_W50_MAXCUT] could not open sim_run_w50_cut_history.csv");
        end
    endtask

    task automatic record_live_sweep_score(
        input int unsigned sweep_idx,
        input int unsigned cycles_since_run_start,
        input bit force_print
    );
        int unsigned cut_value;
        int unsigned broken_chain_count;
        bit improved;
        begin
            score_spins(1'b1, 1'b0, cut_value, broken_chain_count);

            if (sweep_idx < W50_NUM_SWEEPS) begin
                live_cut_history[sweep_idx] = cut_value;
                live_broken_chain_history[sweep_idx] = broken_chain_count;
            end else begin
                error_count++;
                $error("[RUN_W50_MAXCUT] live score sweep index overflow: sweep=%0d max=%0d",
                       sweep_idx + 1, W50_NUM_SWEEPS);
            end

            improved = (live_sample_count == 0) || (cut_value > live_best_cut);
            if (improved) begin
                live_best_cut = cut_value;
                live_best_sweep = sweep_idx + 1;
                live_best_cycle = cycles_since_run_start;
                live_best_broken_chains = broken_chain_count;
            end

            if (sweep_idx < W50_NUM_SWEEPS) begin
                live_best_cut_history[sweep_idx] = live_best_cut;
            end
            live_sample_count++;
            live_final_cut = cut_value;
            live_final_cycle = cycles_since_run_start;
            live_final_broken_chains = broken_chain_count;

            if (live_history_fd != 0) begin
                $fdisplay(live_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                          sweep_idx + 1, cycles_since_run_start, cut_value, live_best_cut,
                          live_best_sweep, live_best_cycle,
                          broken_chain_count, live_best_broken_chains,
                          u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                          u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q,
                          $time);
            end

            if (improved || force_print ||
                (((sweep_idx + 1) % W50_PROGRESS_PRINT_STEP) == 0)) begin
                $display("[RUN_W50_MAXCUT_SWEEP] sweep=%0d cycles=%0d current_cut=%0d best_cut=%0d best_sweep=%0d best_cycle=%0d broken=%0d best_broken=%0d i0=%0d round=%0d",
                         sweep_idx + 1, cycles_since_run_start, cut_value, live_best_cut,
                         live_best_sweep, live_best_cycle,
                         broken_chain_count, live_best_broken_chains,
                         u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                         u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
            end
        end
    endtask

    task automatic start_run_and_wait_done();
        logic [31:0] status;
        int unsigned poll_count;
        int unsigned poll_limit;
        logic [W50_NUM_I0_LEVELS-1:0] saw_round_mask;
        int unsigned completed_sweeps;
        int unsigned run_cycles_since_start;
        bit saw_first_c0_start;
        bit final_sweep_recorded;

        saw_round_mask = '0;
        completed_sweeps = 0;
        run_cycles_since_start = 0;
        saw_first_c0_start = 1'b0;
        final_sweep_recorded = 1'b0;
        init_live_score_history();
        poll_limit = (W50_NUM_SWEEPS * 40) + W50_MIN_RUN_POLL_LIMIT;
        write_reg(A_GLOBAL_CTRL, pack_global_ctrl(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), "cfg done set");

        fork
            begin
                while (u_pbit_top.u_phase_ctrl_4color.run_done_o !== 1'b1) begin
                    @(negedge clk);
                    if (saw_first_c0_start && !final_sweep_recorded) begin
                        run_cycles_since_start++;
                    end
                    if (u_pbit_top.u_phase_ctrl_4color.run_busy_o === 1'b1) begin
                        if (u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q < W50_NUM_I0_LEVELS) begin
                            saw_round_mask[u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q] = 1'b1;
                        end
                    end
                    if (u_pbit_top.phase_start_c0_w === 1'b1) begin
                        if (saw_first_c0_start) begin
                            record_live_sweep_score(completed_sweeps, run_cycles_since_start, 1'b0);
                            completed_sweeps++;
                        end else begin
                            // Count only the hardware run window: cycle 0 is the first C0 start after RUN_START.
                            run_cycles_since_start = 0;
                            saw_first_c0_start = 1'b1;
                        end
                    end
                    if ((u_pbit_top.u_phase_ctrl_4color.run_done_d === 1'b1) && !final_sweep_recorded) begin
                        record_live_sweep_score(completed_sweeps, run_cycles_since_start, 1'b1);
                        completed_sweeps++;
                        final_sweep_recorded = 1'b1;
                    end
                end
            end
            begin
                write_reg(A_GLOBAL_CTRL, pack_global_ctrl(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), "run start");

                poll_count = 0;
                do begin
                    read_reg(A_GLOBAL_STATUS, status, "global status poll");
                    poll_count++;
                    if (poll_count > poll_limit) begin
                        error_count++;
                        dump_run_debug(status);
                        $fatal(1, "[RUN_W50_MAXCUT] timeout waiting RUN_DONE, polls=%0d limit=%0d status=0x%08h time=%0t",
                               poll_count, poll_limit, status, $time);
                    end
                end while (!status[RUN_DONE_MSB:RUN_DONE_LSB]);

                if (status[ERROR_MSB:ERROR_LSB]) begin
                    error_count++;
                    $error("[RUN_W50_MAXCUT] GLOBAL_STATUS.ERROR set, status=0x%08h time=%0t", status, $time);
                end
            end
        join

        if (saw_round_mask !== {W50_NUM_I0_LEVELS{1'b1}}) begin
            error_count++;
            $error("[RUN_W50_MAXCUT] anneal rounds missing, saw_mask=0x%04h expected=0x%04h",
                   saw_round_mask, {W50_NUM_I0_LEVELS{1'b1}});
        end

        if (completed_sweeps != W50_NUM_SWEEPS) begin
            error_count++;
            $error("[RUN_W50_MAXCUT] live score sample count mismatch: sampled=%0d expected=%0d",
                   completed_sweeps, W50_NUM_SWEEPS);
        end
        $display("[RUN_W50_MAXCUT] live_best_cut=%0d best_sweep=%0d best_cycle=%0d live_final_cut=%0d final_cycle=%0d live_final_broken=%0d",
                 live_best_cut, live_best_sweep, live_best_cycle,
                 live_final_cut, live_final_cycle, live_final_broken_chains);
    endtask

    task automatic latch_snapshot_page(input int unsigned page);
        bit saw_snapshot_latch;
        bit saw_snapshot_valid;
        logic [31:0] rdata;

        write_reg(A_SNAPSHOT_ADDR, page[31:0], "snapshot addr");
        saw_snapshot_latch = 1'b0;
        saw_snapshot_valid = 1'b0;

        fork
            begin
                repeat (3000) begin
                    @(posedge clk);
                    if (u_pbit_top.snapshot_latch_pulse_w === 1'b1) begin
                        saw_snapshot_latch = 1'b1;
                    end
                    if (u_pbit_top.snapshot_vld_w === 1'b1) begin
                        saw_snapshot_valid = 1'b1;
                    end
                end
            end
            begin
                write_reg(A_GLOBAL_CTRL, pack_global_ctrl(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0), "snapshot latch");
            end
        join

        if (!saw_snapshot_latch || !saw_snapshot_valid) begin
            error_count++;
            $error("[RUN_W50_MAXCUT] snapshot pulse missing for page=%0d latch=%0b valid=%0b",
                   page, saw_snapshot_latch, saw_snapshot_valid);
        end

        for (int word_idx = 0; word_idx < SPIN_RDATA_REG_NUM; word_idx++) begin
            read_reg(spin_rdata_addr(word_idx), rdata, "spin rdata");
            snapshot_words[page][word_idx] = rdata;
        end
    endtask

    task automatic latch_all_snapshots();
        for (int page = 0; page < W50_SNAPSHOT_PAGES; page++) begin
            latch_snapshot_page(page);
        end
    endtask

    task automatic decode_and_score(
        output int unsigned cut_value,
        output int unsigned broken_chain_count
    );
        score_spins(1'b0, 1'b1, cut_value, broken_chain_count);
    endtask

    initial begin
        int unsigned cut_value;
        int unsigned broken_chain_count;

        error_count = 0;
        uart_rx_i = 1'b1;
        rst_n = 1'b0;
        load_w50_maxcut_data();

        $display("[RUN_W50_MAXCUT] physical=%0d config_edges=%0d clear_edges=%0d logical_edges=%0d",
                 W50_NUM_PHYSICAL, W50_NUM_CONFIG_EDGES, W50_NUM_CLEAR_EDGES, W50_NUM_LOGICAL_EDGES);
        $display("[RUN_W50_MAXCUT] sweeps=%0d majority=%0d min_cut=%0d tile_lfsrs=%0d",
                 W50_NUM_SWEEPS, W50_NUM_MAJORITY, W50_MIN_PASS_CUT, W50_NUM_TILE_LFSRS);

        hard_reset();
        configure_run_registers();
        configure_nodes();
        clear_edges();
        configure_edges();
        start_run_and_wait_done();
        latch_all_snapshots();
        decode_and_score(cut_value, broken_chain_count);

        $display("[RUN_W50_MAXCUT] cut_value=%0d total_weight=%0d min_pass=%0d",
                 cut_value, W50_TOTAL_LOGICAL_WEIGHT, W50_MIN_PASS_CUT);
        if (cut_value != live_final_cut) begin
            error_count++;
            $error("[RUN_W50_MAXCUT] live/snapshot final cut mismatch: live=%0d snapshot=%0d",
                   live_final_cut, cut_value);
        end
        if (broken_chain_count != live_final_broken_chains) begin
            error_count++;
            $error("[RUN_W50_MAXCUT] live/snapshot broken-chain mismatch: live=%0d snapshot=%0d",
                   live_final_broken_chains, broken_chain_count);
        end
        if (live_history_fd != 0) begin
            $fclose(live_history_fd);
            live_history_fd = 0;
        end
        if (cut_value < W50_MIN_PASS_CUT) begin
            error_count++;
            $error("[RUN_W50_MAXCUT] cut below threshold: cut=%0d min=%0d", cut_value, W50_MIN_PASS_CUT);
        end

        if (error_count == 0) begin
            $display("[TB_RUN_W50_MAXCUT] PASS");
        end else begin
            $fatal(1, "[TB_RUN_W50_MAXCUT] FAIL error_count=%0d", error_count);
        end

        $finish;
    end
endmodule
`endif
