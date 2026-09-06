`ifndef TB_RUN_KSAT_10V40C
`define TB_RUN_KSAT_10V40C
import pbit_pkg::*;

module tb;
    timeunit 1ns;
    timeprecision 1ps;
    // Preserve the 2.5 ns PLL-core period without integer truncation.
    localparam realtime CLK_PERIOD_NS = 1_000_000_000.0 / CLK_FREQ_HZ;
    localparam int unsigned UART_BIT_TIME_NS = 1_000_000_000 / BAUD_RATE;
    localparam int unsigned K10_MIN_RUN_POLL_LIMIT = 1200;
    localparam int unsigned K10_PROGRESS_PRINT_STEP = 50;

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

    pbit_top u_pbit_top (
        .clk       (clk),
        .rst_n     (rst_n),
        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o)
    );

    `include "tb_ksat_10v40c_data.svh"

    int unsigned live_satisfied_history [K10_NUM_SWEEPS];
    int unsigned live_unsatisfied_history [K10_NUM_SWEEPS];
    int unsigned live_broken_chain_history [K10_NUM_SWEEPS];
    int unsigned live_sample_count;
    int unsigned live_best_satisfied;
    int unsigned live_min_unsatisfied;
    int unsigned live_first_success_sweep;
    int unsigned live_first_success_cycle;
    int unsigned live_best_broken_chains;
    int unsigned live_final_satisfied;
    int unsigned live_final_cycle;
    int unsigned live_final_unsatisfied;
    int unsigned live_final_broken_chains;
    int unsigned run_first_success_sweep [K10_NUM_SEED_RUNS];
    int unsigned run_first_success_cycle [K10_NUM_SEED_RUNS];
    int unsigned run_best_satisfied [K10_NUM_SEED_RUNS];
    int unsigned run_final_satisfied [K10_NUM_SEED_RUNS];
    int unsigned global_success_count;
    int unsigned global_fastest_success_sweep;
    int unsigned global_fastest_success_cycle;
    int unsigned global_fastest_success_run;
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

    function automatic logic [31:0] pack_global_cfg(
        input logic [NUM_SWEEP_WIDTH-1:0] num_sweeps,
        input logic [NUM_MAJORITY_WIDTH-1:0] num_majority
    );
        pack_global_cfg = '0;
        // RTL_V2_ADAPT: The current RTL stores sweep and majority counts as actual value minus one.
        pack_global_cfg[NUM_SWEEP_MSB:NUM_SWEEP_LSB] = NUM_SWEEP_WIDTH'(num_sweeps - 1);
        pack_global_cfg[NUM_MAJORITY_MSB:NUM_MAJORITY_LSB] = NUM_MAJORITY_WIDTH'(num_majority - 1);
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
        input logic clamp_spin,
        input logic bias_sign,
        input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob
    );
        pack_node_cfg = '0;
        // RTL_V2_ADAPT: Seed validity moved out of NODE_CFG and is controlled by APPLY_SEED.
        pack_node_cfg[INIT_VALID_MSB:INIT_VALID_LSB] = 1'b1;
        pack_node_cfg[CLAMP_VALID_MSB:CLAMP_VALID_LSB] = 1'b1;
        pack_node_cfg[BIAS_VALID_MSB:BIAS_VALID_LSB] = 1'b1;
        pack_node_cfg[NODE_CFG_INIT_SPIN_MSB:NODE_CFG_INIT_SPIN_LSB] = init_spin;
        pack_node_cfg[NODE_CFG_CLAMP_EN_MSB:NODE_CFG_CLAMP_EN_LSB] = clamp_en;
        pack_node_cfg[NODE_CFG_CLAMP_SPIN_MSB:NODE_CFG_CLAMP_SPIN_LSB] = clamp_spin;
        pack_node_cfg[NODE_CFG_BIAS_SIGN_MSB:NODE_CFG_BIAS_SIGN_LSB] = bias_sign;
        pack_node_cfg[NODE_CFG_BIAS_PROB_MSB:NODE_CFG_BIAS_PROB_LSB] = bias_prob;
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
        // RTL_V2_ADAPT: Match the split config/seed command fields in the current register map.
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
        pack_i0_word[I0_LEVEL0_MSB:I0_LEVEL0_LSB] = k10_i0_level[base_idx + 0];
        pack_i0_word[I0_LEVEL1_MSB:I0_LEVEL1_LSB] = k10_i0_level[base_idx + 1];
        pack_i0_word[I0_LEVEL2_MSB:I0_LEVEL2_LSB] = k10_i0_level[base_idx + 2];
        pack_i0_word[I0_LEVEL3_MSB:I0_LEVEL3_LSB] = k10_i0_level[base_idx + 3];
    endfunction

    function automatic logic [31:0] pack_interval_word(input int unsigned base_idx);
        pack_interval_word = '0;
        // RTL_V2_ADAPT: The current RTL stores each sweep interval as actual value minus one.
        pack_interval_word[SWEEP_INTERVAL0_MSB:SWEEP_INTERVAL0_LSB] = SWEEP_INTERVAL_WIDTH'(k10_sweep_interval[base_idx + 0] - 1);
        pack_interval_word[SWEEP_INTERVAL1_MSB:SWEEP_INTERVAL1_LSB] = SWEEP_INTERVAL_WIDTH'(k10_sweep_interval[base_idx + 1] - 1);
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
            $error("[uart receive start] missing start bit time=%0t", $time);
        end
        for (int idx = 0; idx < 8; idx++) begin
            #(UART_BIT_TIME_NS);
            rx_data[idx] = uart_tx_o;
        end
        #(UART_BIT_TIME_NS);
        if (uart_tx_o !== 1'b1) begin
            error_count++;
            $error("[uart receive stop] missing stop bit time=%0t", $time);
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
        logic [7:0] rx_bytes [7];
        fork
            begin
                uart_send_byte(op);
                uart_send_byte(addr[15:8]);
                uart_send_byte(addr[7:0]);
                uart_send_byte(wdata[31:24]);
                uart_send_byte(wdata[23:16]);
                uart_send_byte(wdata[15:8]);
                uart_send_byte(wdata[7:0]);
            end
            begin
                for (int idx = 0; idx < 7; idx++) begin
                    uart_receive_byte(rx_bytes[idx]);
                    case (idx)
                        0: status = status_e'(rx_bytes[idx]);
                        1: raddr[15:8] = rx_bytes[idx];
                        2: raddr[7:0] = rx_bytes[idx];
                        3: rdata[31:24] = rx_bytes[idx];
                        4: rdata[23:16] = rx_bytes[idx];
                        5: rdata[15:8] = rx_bytes[idx];
                        6: rdata[7:0] = rx_bytes[idx];
                        default: begin end
                    endcase
                end
            end
        join
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

        expected_global_cfg = pack_global_cfg(K10_NUM_SWEEPS, K10_NUM_MAJORITY);
        write_reg(A_GLOBAL_CFG, expected_global_cfg, "global cfg");

        for (int reg_idx = 0; reg_idx < (K10_NUM_I0_LEVELS / 4); reg_idx++) begin
            write_reg(reg_addr_stride4(A_I0_LEVEL0, reg_idx), pack_i0_word(reg_idx * 4), "i0 level");
        end

        for (int reg_idx = 0; reg_idx < (K10_NUM_I0_LEVELS / 2); reg_idx++) begin
            write_reg(reg_addr_stride4(A_SWEEP_INTERVAL0, reg_idx), pack_interval_word(reg_idx * 2), "sweep interval");
        end

        read_reg(A_GLOBAL_CFG, rdata, "global cfg readback");
        report_mismatch("global cfg readback", rdata, expected_global_cfg);
    endtask

    task automatic configure_nodes(input int unsigned run_idx);
        bit tile_seeded [SHARED_ROWS][SHARED_COLS];
        int unsigned tile_row;
        int unsigned tile_col;

        // RTL_V2_ADAPT: Apply per-node configuration independently from the shared tile seeds.
        for (int idx = 0; idx < K10_NUM_PHYSICAL; idx++) begin
            write_reg(A_NODE_TARGET,
                      pack_node_target(TARGET_MODE_LOCAL, k10_phys_row[idx], k10_phys_col[idx]),
                      "node target");
            write_reg(A_NODE_CFG,
                       pack_node_cfg(k10_node_init_spin[run_idx][idx], 1'b0, k10_node_init_spin[run_idx][idx],
                                     k10_node_bias_sign[idx], k10_node_bias_prob[idx]),
                       "node cfg");
            write_reg(A_NODE_CMD,
                      pack_node_cmd(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0),
                      "node apply");
            repeat (1) @(posedge clk);
        end

        // RTL_V2_ADAPT: Program one seed per 2x2 shared-LFSR tile using tile coordinates.
        for (int r = 0; r < SHARED_ROWS; r++) begin
            for (int c = 0; c < SHARED_COLS; c++) begin
                tile_seeded[r][c] = 1'b0;
            end
        end

        for (int idx = 0; idx < K10_NUM_PHYSICAL; idx++) begin
            tile_row = k10_phys_row[idx] / 2;
            tile_col = k10_phys_col[idx] / 2;

            if (!tile_seeded[tile_row][tile_col]) begin
                write_reg(A_NODE_TARGET,
                          pack_node_target(TARGET_MODE_LOCAL,
                                           NODE_TARGET_ROW_WIDTH'(tile_row),
                                           NODE_TARGET_COL_WIDTH'(tile_col)),
                          "seed target");
                write_reg(A_NODE_SEED, k10_node_seed[run_idx][idx], "node seed");
                write_reg(A_NODE_CMD,
                          pack_node_cmd(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0),
                          "node apply seed");
                tile_seeded[tile_row][tile_col] = 1'b1;
            end
        end

        // RTL_V2_ADAPT: Commit the staged node configuration and tile seeds with LOAD_NODE.
        write_reg(A_NODE_CMD,
                  pack_node_cmd(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0),
                  "node load");
    endtask

    task automatic clear_edges();
        for (int idx = 0; idx < K10_NUM_CLEAR_EDGES; idx++) begin
            write_reg(A_EDGE_TARGET,
                      pack_edge_target(k10_clear_edge_type[idx], k10_clear_edge_row[idx], k10_clear_edge_col[idx]),
                      "edge clear target");
            write_reg(A_EDGE_CMD, pack_edge_cmd(1'b0, 1'b1, 1'b0), "edge clear");
            repeat (1) @(posedge clk);
        end
    endtask

    task automatic configure_edges();
        for (int idx = 0; idx < K10_NUM_CONFIG_EDGES; idx++) begin
            write_reg(A_EDGE_TARGET,
                      pack_edge_target(k10_edge_type[idx], k10_edge_row[idx], k10_edge_col[idx]),
                      "edge target");
            write_reg(A_EDGE_CFG,
                      pack_edge_cfg(k10_edge_prob[idx], k10_edge_sign[idx], 1'b1),
                      "edge cfg");
            write_reg(A_EDGE_CMD, pack_edge_cmd(1'b1, 1'b0, 1'b0), "edge apply");
            repeat (1) @(posedge clk);
        end
    endtask

    task automatic dump_run_debug(input logic [31:0] status);
        $display("[RUN_KSAT_10V40C_DEBUG] status=0x%08h time=%0t", status, $time);
        $display("[RUN_KSAT_10V40C_DEBUG] phase_state=%0d sweep_cnt=%0d round=%0d i0=%0d run_busy=%0b run_done=%0b",
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
            flat_idx = (k10_phys_row[phys_idx] * COLS) + k10_phys_col[phys_idx];
            physical_spin_live = u_pbit_top.u_pbit_array_kings.spin_flat[flat_idx];
        end
    endfunction

    task automatic score_sat_live(
        input  bit print_assignment,
        output int unsigned satisfied,
        output int unsigned unsatisfied,
        output int unsigned broken_chain_count
    );
        logic logical_spin [K10_NUM_LOGICAL];
        logic clause_satisfied;
        logic variable_value;
        logic literal_value;
        int signed chain_sum;
        int signed chain_sum_abs;
        int unsigned chain_len;
        int unsigned lit_idx;

        broken_chain_count = 0;
        for (int logical_idx = 0; logical_idx < K10_NUM_LOGICAL; logical_idx++) begin
            chain_sum = 0;
            for (int p = k10_chain_start[logical_idx]; p < k10_chain_start[logical_idx + 1]; p++) begin
                chain_sum += physical_spin_live(k10_chain_phys_idx[p]) ? 1 : -1;
            end
            chain_len = k10_chain_start[logical_idx + 1] - k10_chain_start[logical_idx];
            chain_sum_abs = (chain_sum < 0) ? -chain_sum : chain_sum;
            if (chain_sum_abs != chain_len) begin
                broken_chain_count++;
            end
            logical_spin[logical_idx] = (chain_sum >= 0);
        end

        satisfied = 0;
        for (int clause_idx = 0; clause_idx < K10_NUM_CLAUSES; clause_idx++) begin
            clause_satisfied = 1'b0;
            for (int lit = 0; lit < K10_LITS_PER_CLAUSE; lit++) begin
                lit_idx = (clause_idx * K10_LITS_PER_CLAUSE) + lit;
                variable_value = logical_spin[k10_clause_var[lit_idx]];
                literal_value = k10_clause_pos[lit_idx] ? variable_value : !variable_value;
                clause_satisfied = clause_satisfied | literal_value;
            end
            if (clause_satisfied) begin
                satisfied++;
            end
        end
        unsatisfied = K10_NUM_CLAUSES - satisfied;

        if (print_assignment) begin
            $display("[RUN_KSAT_10V40C] assignment x[0:9]=%0b%0b%0b%0b%0b%0b%0b%0b%0b%0b",
                     logical_spin[0], logical_spin[1], logical_spin[2], logical_spin[3], logical_spin[4],
                     logical_spin[5], logical_spin[6], logical_spin[7], logical_spin[8], logical_spin[9]);
            $display("[RUN_KSAT_10V40C] satisfied=%0d/%0d unsatisfied=%0d broken_chains=%0d/%0d",
                     satisfied, K10_NUM_CLAUSES, unsatisfied, broken_chain_count, K10_NUM_LOGICAL);
        end
    endtask

    task automatic init_live_score_history(input int unsigned run_idx);
        string history_path;
        for (int sweep = 0; sweep < K10_NUM_SWEEPS; sweep++) begin
            live_satisfied_history[sweep] = 0;
            live_unsatisfied_history[sweep] = K10_NUM_CLAUSES;
            live_broken_chain_history[sweep] = 0;
        end
        live_sample_count = 0;
        live_best_satisfied = 0;
        live_min_unsatisfied = K10_NUM_CLAUSES;
        live_first_success_sweep = 0;
        live_first_success_cycle = 0;
        live_best_broken_chains = 0;
        live_final_satisfied = 0;
        live_final_cycle = 0;
        live_final_unsatisfied = K10_NUM_CLAUSES;
        live_final_broken_chains = 0;
        history_path = $sformatf("sim_run_ksat_10v40c_run%0d_history.csv", run_idx);
        live_history_fd = $fopen(history_path, "w");
        if (live_history_fd != 0) begin
            $fdisplay(live_history_fd, "run,sweep,cycles_since_run_start,satisfied,unsatisfied,best_satisfied,min_unsatisfied,first_success_sweep,first_success_cycle,broken_chains,best_broken_chains,i0_level,round,time");
        end else begin
            $display("[RUN_KSAT_10V40C] could not open %s", history_path);
        end
    endtask

    task automatic record_live_sweep_score(
        input int unsigned run_idx,
        input int unsigned sweep_idx,
        input int unsigned cycles_since_run_start,
        input bit force_print
    );
        int unsigned satisfied;
        int unsigned unsatisfied;
        int unsigned broken_chain_count;
        bit improved;
        begin
            score_sat_live(1'b0, satisfied, unsatisfied, broken_chain_count);

            if (sweep_idx < K10_NUM_SWEEPS) begin
                live_satisfied_history[sweep_idx] = satisfied;
                live_unsatisfied_history[sweep_idx] = unsatisfied;
                live_broken_chain_history[sweep_idx] = broken_chain_count;
            end else begin
                error_count++;
                $error("[RUN_KSAT_10V40C] live score sweep index overflow: sweep=%0d max=%0d",
                       sweep_idx + 1, K10_NUM_SWEEPS);
            end

            improved = (live_sample_count == 0) || (satisfied > live_best_satisfied);
            if (improved) begin
                live_best_satisfied = satisfied;
                live_min_unsatisfied = unsatisfied;
                live_best_broken_chains = broken_chain_count;
            end
            if ((satisfied == K10_NUM_CLAUSES) && (live_first_success_sweep == 0)) begin
                live_first_success_sweep = sweep_idx + 1;
                live_first_success_cycle = cycles_since_run_start;
            end

            live_sample_count++;
            live_final_satisfied = satisfied;
            live_final_cycle = cycles_since_run_start;
            live_final_unsatisfied = unsatisfied;
            live_final_broken_chains = broken_chain_count;

            if (live_history_fd != 0) begin
                $fdisplay(live_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                          run_idx, sweep_idx + 1, cycles_since_run_start,
                          satisfied, unsatisfied, live_best_satisfied, live_min_unsatisfied,
                          live_first_success_sweep, live_first_success_cycle,
                          broken_chain_count, live_best_broken_chains,
                          u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                          u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q,
                          $time);
            end

            if (improved || force_print || (live_first_success_sweep == (sweep_idx + 1)) ||
                (((sweep_idx + 1) % K10_PROGRESS_PRINT_STEP) == 0)) begin
                $display("[RUN_KSAT_10V40C_SWEEP] run=%0d sweep=%0d cycles=%0d satisfied=%0d/%0d best=%0d min_unsat=%0d first_success=%0d first_success_cycle=%0d broken=%0d i0=%0d round=%0d",
                         run_idx, sweep_idx + 1, cycles_since_run_start,
                         satisfied, K10_NUM_CLAUSES, live_best_satisfied,
                         live_min_unsatisfied, live_first_success_sweep, live_first_success_cycle, broken_chain_count,
                         u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                         u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
            end
        end
    endtask

    task automatic start_run_and_wait_done(input int unsigned run_idx);
        logic [31:0] status;
        int unsigned poll_count;
        int unsigned poll_limit;
        logic [K10_NUM_I0_LEVELS-1:0] saw_round_mask;
        int unsigned completed_sweeps;
        int unsigned run_cycles_since_start;
        bit saw_first_c0_start;
        bit final_sweep_recorded;

        saw_round_mask = '0;
        completed_sweeps = 0;
        run_cycles_since_start = 0;
        saw_first_c0_start = 1'b0;
        final_sweep_recorded = 1'b0;
        init_live_score_history(run_idx);
        poll_limit = (K10_NUM_SWEEPS * 40) + K10_MIN_RUN_POLL_LIMIT;
        write_reg(A_GLOBAL_CTRL, pack_global_ctrl(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), "cfg done set");

        fork
            begin
                while (u_pbit_top.u_phase_ctrl_4color.run_done_o !== 1'b1) begin
                    @(negedge clk);
                    if (saw_first_c0_start && !final_sweep_recorded) begin
                        run_cycles_since_start++;
                    end
                    if (u_pbit_top.u_phase_ctrl_4color.run_busy_o === 1'b1) begin
                        if (u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q < K10_NUM_I0_LEVELS) begin
                            saw_round_mask[u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q] = 1'b1;
                        end
                    end
                    if (u_pbit_top.phase_start_c0_w === 1'b1) begin
                        if (saw_first_c0_start) begin
                            record_live_sweep_score(run_idx, completed_sweeps, run_cycles_since_start, 1'b0);
                            completed_sweeps++;
                        end else begin
                            // Count only the hardware run window: cycle 0 is the first C0 start after RUN_START.
                            run_cycles_since_start = 0;
                            saw_first_c0_start = 1'b1;
                        end
                    end
                    if ((u_pbit_top.u_phase_ctrl_4color.run_done_d === 1'b1) && !final_sweep_recorded) begin
                        record_live_sweep_score(run_idx, completed_sweeps, run_cycles_since_start, 1'b1);
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
                        $fatal(1, "[RUN_KSAT_10V40C] timeout waiting RUN_DONE, polls=%0d limit=%0d status=0x%08h time=%0t",
                               poll_count, poll_limit, status, $time);
                    end
                end while (!status[RUN_DONE_MSB:RUN_DONE_LSB]);

                if (status[ERROR_MSB:ERROR_LSB]) begin
                    error_count++;
                    $error("[RUN_KSAT_10V40C] GLOBAL_STATUS.ERROR set, status=0x%08h time=%0t", status, $time);
                end
            end
        join

        if (saw_round_mask !== {K10_NUM_I0_LEVELS{1'b1}}) begin
            error_count++;
            $error("[RUN_KSAT_10V40C] anneal rounds missing, saw_mask=0x%04h expected=0x%04h",
                   saw_round_mask, {K10_NUM_I0_LEVELS{1'b1}});
        end

        if (completed_sweeps != K10_NUM_SWEEPS) begin
            error_count++;
            $error("[RUN_KSAT_10V40C] live score sample count mismatch: sampled=%0d expected=%0d",
                   completed_sweeps, K10_NUM_SWEEPS);
        end
    endtask

    initial begin
        int unsigned final_satisfied;
        int unsigned final_unsatisfied;
        int unsigned final_broken_chains;

        error_count = 0;
        uart_rx_i = 1'b1;
        rst_n = 1'b0;
        load_ksat_10v40c_data();
        global_success_count = 0;
        global_fastest_success_sweep = 0;
        global_fastest_success_cycle = 0;
        global_fastest_success_run = 0;
        for (int run_idx = 0; run_idx < K10_NUM_SEED_RUNS; run_idx++) begin
            run_first_success_sweep[run_idx] = 0;
            run_first_success_cycle[run_idx] = 0;
            run_best_satisfied[run_idx] = 0;
            run_final_satisfied[run_idx] = 0;
        end

        $display("[RUN_KSAT_10V40C] variables=%0d clauses=%0d logical=%0d physical=%0d config_edges=%0d clear_edges=%0d",
                 K10_NUM_VARIABLES, K10_NUM_CLAUSES, K10_NUM_LOGICAL, K10_NUM_PHYSICAL,
                 K10_NUM_CONFIG_EDGES, K10_NUM_CLEAR_EDGES);
        $display("[RUN_KSAT_10V40C] seed_runs=%0d sweeps=%0d majority=%0d min_sat=%0d fixed_i0_level=%0d tile_lfsrs=%0d",
                 K10_NUM_SEED_RUNS, K10_NUM_SWEEPS, K10_NUM_MAJORITY, K10_MIN_PASS_SAT,
                 K10_FIXED_I0_LEVEL, K10_NUM_TILE_LFSRS);
        $display("[RUN_KSAT_10V40C] seed_master_start=%0d seed_master_step=%0d run_seed_start=%0d",
                 K10_SEED_MASTER_START, K10_SEED_MASTER_STEP, K10_RUN_SEED_START);

        for (int run_idx = 0; run_idx < K10_NUM_SEED_RUNS; run_idx++) begin
            $display("[RUN_KSAT_10V40C_RUN] run=%0d global_seed=0x%08h start", run_idx, k10_global_seed[run_idx]);
            hard_reset();
            configure_run_registers();
            configure_nodes(run_idx);
            clear_edges();
            configure_edges();
            start_run_and_wait_done(run_idx);
            score_sat_live(1'b1, final_satisfied, final_unsatisfied, final_broken_chains);

            if (live_history_fd != 0) begin
                $fclose(live_history_fd);
                live_history_fd = 0;
            end

            if (final_satisfied != live_final_satisfied) begin
                error_count++;
                $error("[RUN_KSAT_10V40C] run=%0d final/live satisfied mismatch: final=%0d live=%0d",
                       run_idx, final_satisfied, live_final_satisfied);
            end
            if (final_unsatisfied != live_final_unsatisfied) begin
                error_count++;
                $error("[RUN_KSAT_10V40C] run=%0d final/live unsatisfied mismatch: final=%0d live=%0d",
                       run_idx, final_unsatisfied, live_final_unsatisfied);
            end

            run_first_success_sweep[run_idx] = live_first_success_sweep;
            run_first_success_cycle[run_idx] = live_first_success_cycle;
            run_best_satisfied[run_idx] = live_best_satisfied;
            run_final_satisfied[run_idx] = final_satisfied;

            if (live_first_success_sweep != 0) begin
                global_success_count++;
                if ((global_fastest_success_sweep == 0) ||
                    (live_first_success_sweep < global_fastest_success_sweep) ||
                    ((live_first_success_sweep == global_fastest_success_sweep) &&
                     (live_first_success_cycle < global_fastest_success_cycle))) begin
                    global_fastest_success_sweep = live_first_success_sweep;
                    global_fastest_success_cycle = live_first_success_cycle;
                    global_fastest_success_run = run_idx;
                end
            end

            $display("[RUN_KSAT_10V40C_RUN] run=%0d best_satisfied=%0d/%0d first_success_sweep=%0d first_success_cycle=%0d final_satisfied=%0d/%0d final_unsatisfied=%0d final_cycle=%0d",
                     run_idx, live_best_satisfied, K10_NUM_CLAUSES, live_first_success_sweep,
                     live_first_success_cycle, final_satisfied, K10_NUM_CLAUSES,
                     final_unsatisfied, live_final_cycle);
        end

        $display("[RUN_KSAT_10V40C_SUMMARY] success_count=%0d/%0d fastest_run=%0d fastest_first_success_sweep=%0d fastest_first_success_cycle=%0d",
                 global_success_count, K10_NUM_SEED_RUNS, global_fastest_success_run,
                 global_fastest_success_sweep, global_fastest_success_cycle);
        for (int run_idx = 0; run_idx < K10_NUM_SEED_RUNS; run_idx++) begin
            $display("[RUN_KSAT_10V40C_SUMMARY] run=%0d first_success_sweep=%0d first_success_cycle=%0d best_satisfied=%0d/%0d final_satisfied=%0d/%0d",
                     run_idx, run_first_success_sweep[run_idx], run_first_success_cycle[run_idx],
                     run_best_satisfied[run_idx],
                     K10_NUM_CLAUSES, run_final_satisfied[run_idx], K10_NUM_CLAUSES);
        end

        if (global_success_count == 0) begin
            error_count++;
            $error("[RUN_KSAT_10V40C] no seed run reached SAT threshold min=%0d", K10_MIN_PASS_SAT);
        end

        if (error_count == 0) begin
            $display("[TB_RUN_KSAT_10V40C] PASS");
        end else begin
            $fatal(1, "[TB_RUN_KSAT_10V40C] FAIL error_count=%0d", error_count);
        end

        $finish;
    end
endmodule
`endif
