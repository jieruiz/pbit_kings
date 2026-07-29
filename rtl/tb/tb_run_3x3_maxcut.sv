`ifndef TB_RUN_3X3_MAXCUT
`define TB_RUN_3X3_MAXCUT
import pbit_pkg::*;

module tb_run_3x3_maxcut;
    localparam int unsigned CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;
    localparam int unsigned UART_BIT_TIME_NS = 1_000_000_000 / BAUD_RATE;
    localparam int unsigned MAXCUT_OPT_SCORE = 14;
    localparam int unsigned MAXCUT_MIN_PASS_SCORE = 13;

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

    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    function automatic logic init_spin_for(
        input int unsigned row,
        input int unsigned col,
        input int unsigned mode
    );
        case (mode)
            0: init_spin_for = (row + col) & 1;
            1: init_spin_for = 1'b0;
            default: init_spin_for = (row == col) || ((row + col) == 3);
        endcase
    endfunction

    function automatic int unsigned cut_score_3x3(input logic [8:0] spins);
        int unsigned score;
        begin
            score = 0;
            score += (spins[0] != spins[1]);
            score += (spins[1] != spins[2]);
            score += (spins[3] != spins[4]);
            score += (spins[4] != spins[5]);
            score += (spins[6] != spins[7]);
            score += (spins[7] != spins[8]);
            score += (spins[0] != spins[3]);
            score += (spins[1] != spins[4]);
            score += (spins[2] != spins[5]);
            score += (spins[3] != spins[6]);
            score += (spins[4] != spins[7]);
            score += (spins[5] != spins[8]);
            score += (spins[0] != spins[4]);
            score += (spins[1] != spins[5]);
            score += (spins[3] != spins[7]);
            score += (spins[4] != spins[8]);
            score += (spins[1] != spins[3]);
            score += (spins[2] != spins[4]);
            score += (spins[4] != spins[6]);
            score += (spins[5] != spins[7]);
            cut_score_3x3 = score;
        end
    endfunction

    function automatic logic [31:0] pack_global_cfg(
        input logic [NUM_SWEEP_WIDTH-1:0] num_sweeps,
        input logic [NUM_MAJORITY_WIDTH-1:0] num_majority
    );
        pack_global_cfg = '0;
        pack_global_cfg[NUM_SWEEP_MSB:NUM_SWEEP_LSB] = num_sweeps;
        pack_global_cfg[NUM_MAJORITY_MSB:NUM_MAJORITY_LSB] = num_majority;
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

    function automatic logic [31:0] pack_i0_levels(
        input logic [I0_LEVEL_WIDTH-1:0] l0,
        input logic [I0_LEVEL_WIDTH-1:0] l1,
        input logic [I0_LEVEL_WIDTH-1:0] l2,
        input logic [I0_LEVEL_WIDTH-1:0] l3
    );
        pack_i0_levels = '0;
        pack_i0_levels[I0_LEVEL0_MSB:I0_LEVEL0_LSB] = l0;
        pack_i0_levels[I0_LEVEL1_MSB:I0_LEVEL1_LSB] = l1;
        pack_i0_levels[I0_LEVEL2_MSB:I0_LEVEL2_LSB] = l2;
        pack_i0_levels[I0_LEVEL3_MSB:I0_LEVEL3_LSB] = l3;
    endfunction

    function automatic logic [31:0] pack_sweep_intervals(
        input logic [SWEEP_INTERVAL_WIDTH-1:0] i0,
        input logic [SWEEP_INTERVAL_WIDTH-1:0] i1
    );
        pack_sweep_intervals = '0;
        pack_sweep_intervals[SWEEP_INTERVAL0_MSB:SWEEP_INTERVAL0_LSB] = i0;
        pack_sweep_intervals[SWEEP_INTERVAL1_MSB:SWEEP_INTERVAL1_LSB] = i1;
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
        pack_node_cfg[SEED_VALID_MSB:SEED_VALID_LSB] = 1'b1;
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
        input logic load_cfg,
        input logic clear_scope_en,
        input logic clear_local_all,
        input logic readback_node
    );
        pack_node_cmd = '0;
        pack_node_cmd[APPLY_CFG_MSB:APPLY_CFG_LSB] = apply_cfg;
        pack_node_cmd[LOAD_CFG_MSB:LOAD_CFG_LSB] = load_cfg;
        pack_node_cmd[CLEAR_SCOPE_EN_MSB:CLEAR_SCOPE_EN_LSB] = clear_scope_en;
        pack_node_cmd[CLEAR_LOCAL_ALL_MSB:CLEAR_LOCAL_ALL_LSB] = clear_local_all;
        pack_node_cmd[READBACK_NODE_MSB:READBACK_NODE_LSB] = readback_node;
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

    task automatic configure_one_node(
        input int unsigned row,
        input int unsigned col,
        input logic [31:0] seed_base,
        input int unsigned init_mode
    );
        logic spin_value;
        logic [31:0] seed;

        spin_value = init_spin_for(row, col, init_mode);
        seed = seed_base + (row * 16) + col;

        write_reg(A_NODE_TARGET, pack_node_target(TARGET_MODE_LOCAL, row[5:0], col[5:0]), "node target");
        write_reg(A_NODE_CFG, pack_node_cfg(spin_value, 1'b0, spin_value), "node cfg");
        write_reg(A_NODE_SEED, seed, "node seed");
        write_reg(A_NODE_CMD, pack_node_cmd(1'b1, 1'b0, 1'b0, 1'b0, 1'b0), "node apply");
        repeat (2) @(posedge clk);
    endtask

    task automatic configure_3x3_nodes(
        input logic [31:0] seed_base,
        input int unsigned init_mode
    );
        for (int r = 0; r < 3; r++) begin
            for (int c = 0; c < 3; c++) begin
                configure_one_node(r, c, seed_base, init_mode);
            end
        end
    endtask

    task automatic configure_one_edge(
        input logic [EDGE_TYPE_WIDTH-1:0] edge_type,
        input int unsigned row,
        input int unsigned col,
        input logic sign,
        input logic valid
    );
        write_reg(A_EDGE_TARGET, pack_edge_target(edge_type, row[5:0], col[5:0]), "edge target");
        write_reg(A_EDGE_CFG, pack_edge_cfg(7'h7f, sign, valid), "edge cfg");
        write_reg(A_EDGE_CMD, pack_edge_cmd(1'b1, 1'b0, 1'b0), "edge apply");
        repeat (2) @(posedge clk);
    endtask

    task automatic clear_one_edge(
        input logic [EDGE_TYPE_WIDTH-1:0] edge_type,
        input int unsigned row,
        input int unsigned col
    );
        write_reg(A_EDGE_TARGET, pack_edge_target(edge_type, row[5:0], col[5:0]), "edge clear target");
        write_reg(A_EDGE_CMD, pack_edge_cmd(1'b0, 1'b1, 1'b0), "edge clear");
        repeat (2) @(posedge clk);
    endtask

    task automatic configure_3x3_maxcut_edges();
        for (int r = 0; r < 3; r++) begin
            for (int c = 0; c < 2; c++) begin
                configure_one_edge(EDGE_TYPE_EDGE_H, r, c, 1'b0, 1'b1);
            end
        end

        for (int r = 0; r < 2; r++) begin
            for (int c = 0; c < 3; c++) begin
                configure_one_edge(EDGE_TYPE_EDGE_V, r, c, 1'b0, 1'b1);
            end
        end

        for (int r = 0; r < 2; r++) begin
            for (int c = 0; c < 2; c++) begin
                configure_one_edge(EDGE_TYPE_EDGE_DSE, r, c, 1'b0, 1'b1);
            end
        end

        for (int r = 0; r < 2; r++) begin
            for (int c = 1; c < 3; c++) begin
                configure_one_edge(EDGE_TYPE_EDGE_DSW, r, c, 1'b0, 1'b1);
            end
        end
    endtask

    task automatic clear_3x3_external_edges();
        for (int r = 0; r < 3; r++) begin
            clear_one_edge(EDGE_TYPE_EDGE_H, r, 2);
        end

        for (int c = 0; c < 3; c++) begin
            clear_one_edge(EDGE_TYPE_EDGE_V, 2, c);
        end

        for (int r = 0; r < 2; r++) begin
            clear_one_edge(EDGE_TYPE_EDGE_DSE, r, 2);
        end
        for (int c = 0; c < 3; c++) begin
            clear_one_edge(EDGE_TYPE_EDGE_DSE, 2, c);
        end

        clear_one_edge(EDGE_TYPE_EDGE_DSW, 2, 1);
        clear_one_edge(EDGE_TYPE_EDGE_DSW, 2, 2);
        clear_one_edge(EDGE_TYPE_EDGE_DSW, 0, 3);
        clear_one_edge(EDGE_TYPE_EDGE_DSW, 1, 3);
    endtask

    task automatic configure_run_registers();
        logic [31:0] rdata;
        logic [31:0] expected_global_cfg;
        logic [31:0] expected_i0_0;
        logic [31:0] expected_si_0;
        logic [31:0] expected_si_1;

        expected_global_cfg = pack_global_cfg(24'd6, NUM_MAJORITY_WIDTH'(5));
        expected_i0_0 = pack_i0_levels(6'd4, 6'd16, 6'd48, 6'd0);
        expected_si_0 = pack_sweep_intervals(16'd2, 16'd2);
        expected_si_1 = pack_sweep_intervals(16'd2, 16'd0);

        write_reg(A_GLOBAL_CFG, expected_global_cfg, "global cfg");
        write_reg(A_I0_LEVEL0, expected_i0_0, "i0 level0");
        write_reg(A_SWEEP_INTERVAL0, expected_si_0, "sweep interval0");
        write_reg(A_SWEEP_INTERVAL1, expected_si_1, "sweep interval1");

        read_reg(A_GLOBAL_CFG, rdata, "global cfg readback");
        report_mismatch("global cfg readback", rdata, expected_global_cfg);
        read_reg(A_I0_LEVEL0, rdata, "i0 level0 readback");
        report_mismatch("i0 level0 readback", rdata, expected_i0_0);
        read_reg(A_SWEEP_INTERVAL0, rdata, "sweep interval0 readback");
        report_mismatch("sweep interval0 readback", rdata, expected_si_0);
        read_reg(A_SWEEP_INTERVAL1, rdata, "sweep interval1 readback");
        report_mismatch("sweep interval1 readback", rdata, expected_si_1);
    endtask

    task automatic dump_run_debug(input logic [31:0] status);
        $display("[RUN_3X3_MAXCUT_DEBUG] status=0x%08h time=%0t", status, $time);
        $display("[RUN_3X3_MAXCUT_DEBUG] phase_state=%0d sweep_cnt=%0d round=%0d i0=%0d run_busy=%0b run_done=%0b",
                 u_pbit_top.u_phase_ctrl_4color.state_q,
                 u_pbit_top.u_phase_ctrl_4color.sweep_cnt_q,
                 u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q,
                 u_pbit_top.i0_level_w,
                 u_pbit_top.u_phase_ctrl_4color.run_busy_o,
                 u_pbit_top.u_phase_ctrl_4color.run_done_o);
        $display("[RUN_3X3_MAXCUT_DEBUG] done_cnt={%0d,%0d,%0d,%0d} cnt_max=%0d num_majority=%0d",
                 u_pbit_top.u_pbit_array_kings.done_c3_cnt_q,
                 u_pbit_top.u_pbit_array_kings.done_c2_cnt_q,
                 u_pbit_top.u_pbit_array_kings.done_c1_cnt_q,
                 u_pbit_top.u_pbit_array_kings.done_c0_cnt_q,
                 u_pbit_top.u_pbit_array_kings.cnt_max,
                 u_pbit_top.u_pbit_array_kings.num_majority_i);
    endtask

    task automatic start_run_and_wait_done(
        output logic saw_i0_4,
        output logic saw_i0_16,
        output logic saw_i0_48
    );
        logic [31:0] status;
        int unsigned poll_count;

        saw_i0_4 = 1'b0;
        saw_i0_16 = 1'b0;
        saw_i0_48 = 1'b0;

        write_reg(A_GLOBAL_CTRL, pack_global_ctrl(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0), "cfg done set");

        fork
            begin
                while (u_pbit_top.u_phase_ctrl_4color.run_done_o !== 1'b1) begin
                    @(posedge clk);
                    if (u_pbit_top.u_phase_ctrl_4color.run_busy_o === 1'b1) begin
                        if (u_pbit_top.i0_level_w === 6'd4) begin
                            saw_i0_4 = 1'b1;
                        end
                        if (u_pbit_top.i0_level_w === 6'd16) begin
                            saw_i0_16 = 1'b1;
                        end
                        if (u_pbit_top.i0_level_w === 6'd48) begin
                            saw_i0_48 = 1'b1;
                        end
                    end
                end
            end
            begin
                write_reg(A_GLOBAL_CTRL, pack_global_ctrl(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0), "run start");

                poll_count = 0;
                do begin
                    read_reg(A_GLOBAL_STATUS, status, "global status poll");
                    poll_count++;
                    if (poll_count > 500) begin
                        error_count++;
                        dump_run_debug(status);
                        $fatal(1, "[RUN_3X3_MAXCUT] timeout waiting RUN_DONE, status=0x%08h time=%0t", status, $time);
                    end
                end while (!status[RUN_DONE_MSB:RUN_DONE_LSB]);

                if (status[ERROR_MSB:ERROR_LSB]) begin
                    error_count++;
                    $error("[RUN_3X3_MAXCUT] GLOBAL_STATUS.ERROR set, status=0x%08h time=%0t", status, $time);
                end
            end
        join
    endtask

    task automatic latch_snapshot0();
        bit saw_snapshot_latch;
        bit saw_snapshot_valid;
        write_reg(A_SNAPSHOT_ADDR, 32'd0, "snapshot addr");

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

        if (!saw_snapshot_latch) begin
            error_count++;
            $error("[RUN_3X3_MAXCUT] snapshot latch pulse was not observed time=%0t", $time);
        end
        if (!saw_snapshot_valid) begin
            error_count++;
            $error("[RUN_3X3_MAXCUT] snapshot valid pulse was not observed time=%0t", $time);
        end
    endtask

    task automatic read_3x3_snapshot(output logic [8:0] spins);
        logic [31:0] spin0;
        logic [31:0] spin1;
        logic [31:0] spin2;

        read_reg(A_SPIN_RDATA0, spin0, "spin rdata0");
        read_reg(A_SPIN_RDATA1, spin1, "spin rdata1");
        read_reg(A_SPIN_RDATA2, spin2, "spin rdata2");

        spins[0] = spin0[0];
        spins[1] = spin0[1];
        spins[2] = spin0[2];
        spins[3] = spin1[8];
        spins[4] = spin1[9];
        spins[5] = spin1[10];
        spins[6] = spin2[16];
        spins[7] = spin2[17];
        spins[8] = spin2[18];
    endtask

    task automatic run_maxcut_trial(
        input int unsigned trial_id,
        input logic [31:0] seed_base,
        input int unsigned init_mode,
        output int unsigned score_o,
        output logic [8:0] spins_o
    );
        logic saw_i0_4;
        logic saw_i0_16;
        logic saw_i0_48;

        $display("[RUN_3X3_MAXCUT] start trial=%0d seed_base=0x%08h init_mode=%0d", trial_id, seed_base, init_mode);
        hard_reset();
        configure_run_registers();
        configure_3x3_nodes(seed_base, init_mode);
        clear_3x3_external_edges();
        configure_3x3_maxcut_edges();
        start_run_and_wait_done(saw_i0_4, saw_i0_16, saw_i0_48);
        latch_snapshot0();
        read_3x3_snapshot(spins_o);
        score_o = cut_score_3x3(spins_o);

        if (!(saw_i0_4 && saw_i0_16 && saw_i0_48)) begin
            error_count++;
            $error("[RUN_3X3_MAXCUT] anneal schedule missing level, saw={4:%0b,16:%0b,48:%0b} time=%0t",
                   saw_i0_4, saw_i0_16, saw_i0_48, $time);
        end

        $display("[RUN_3X3_MAXCUT] trial=%0d score=%0d pattern=%0b%0b%0b/%0b%0b%0b/%0b%0b%0b",
                 trial_id,
                 score_o,
                 spins_o[0], spins_o[1], spins_o[2],
                 spins_o[3], spins_o[4], spins_o[5],
                 spins_o[6], spins_o[7], spins_o[8]);
    endtask

    initial begin
        int unsigned score;
        int unsigned best_score;
        logic [8:0] spins;
        logic [8:0] best_spins;

        error_count = 0;
        uart_rx_i = 1'b1;
        rst_n = 1'b0;
        best_score = 0;
        best_spins = '0;

        run_maxcut_trial(0, 32'h6100_0001, 0, score, spins);
        if (score > best_score) begin
            best_score = score;
            best_spins = spins;
        end

        if (best_score < MAXCUT_OPT_SCORE) begin
            run_maxcut_trial(1, 32'h6200_0001, 1, score, spins);
            if (score > best_score) begin
                best_score = score;
                best_spins = spins;
            end
        end

        if (best_score < MAXCUT_OPT_SCORE) begin
            run_maxcut_trial(2, 32'h6300_0001, 2, score, spins);
            if (score > best_score) begin
                best_score = score;
                best_spins = spins;
            end
        end

        $display("[RUN_3X3_MAXCUT] best_score=%0d pattern=%0b%0b%0b/%0b%0b%0b/%0b%0b%0b",
                 best_score,
                 best_spins[0], best_spins[1], best_spins[2],
                 best_spins[3], best_spins[4], best_spins[5],
                 best_spins[6], best_spins[7], best_spins[8]);

        if (best_score < MAXCUT_MIN_PASS_SCORE) begin
            error_count++;
            $error("[RUN_3X3_MAXCUT] best score below threshold, best=%0d threshold=%0d optimal=%0d",
                   best_score, MAXCUT_MIN_PASS_SCORE, MAXCUT_OPT_SCORE);
        end

        if (best_score == MAXCUT_OPT_SCORE) begin
            $display("[RUN_3X3_MAXCUT] reached optimal maxcut score=%0d", best_score);
        end else begin
            $display("[RUN_3X3_MAXCUT] reached near-optimal score=%0d, optimal=%0d", best_score, MAXCUT_OPT_SCORE);
        end

        if (error_count == 0) begin
            $display("[TB_RUN_3X3_MAXCUT] PASS");
        end else begin
            $fatal(1, "[TB_RUN_3X3_MAXCUT] FAIL error_count=%0d", error_count);
        end

        $finish;
    end
endmodule
`endif
