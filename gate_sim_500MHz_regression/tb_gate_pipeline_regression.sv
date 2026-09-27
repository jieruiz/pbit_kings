`timescale 1ns/1ps

// Additional pin-only regressions for the synthesized 20x20/3200-p-bit
// wrapper. All configuration and observation use the production UART path.
module tb_gate_pipeline_regression;
    localparam logic [15:0] A_GLOBAL_CTRL     = 16'h0000;
    localparam logic [15:0] A_GLOBAL_CFG      = 16'h0004;
    localparam logic [15:0] A_GLOBAL_STATUS   = 16'h0008;
    localparam logic [15:0] A_ERROR_STATUS    = 16'h000c;
    localparam logic [15:0] A_SNAPSHOT_ADDR   = 16'h0010;
    localparam logic [15:0] A_I0_LEVEL0       = 16'h0014;
    localparam logic [15:0] A_SWEEP_INTERVAL0 = 16'h0034;
    localparam logic [15:0] A_UNIT_TARGET     = 16'h0074;
    localparam logic [15:0] A_NODE_TARGET     = 16'h0078;
    localparam logic [15:0] A_NODE_CFG        = 16'h007c;
    localparam logic [15:0] A_NODE_CMD        = 16'h0080;
    localparam logic [15:0] A_NODE_RDATA_CFG  = 16'h0084;
    localparam logic [15:0] A_SEED_TARGET     = 16'h0088;
    localparam logic [15:0] A_SEED            = 16'h008c;
    localparam logic [15:0] A_SEED_CMD        = 16'h0090;
    localparam logic [15:0] A_SEED_RDATA      = 16'h0094;
    localparam logic [15:0] A_EDGE_TARGET     = 16'h0098;
    localparam logic [15:0] A_EDGE_CFG        = 16'h009c;
    localparam logic [15:0] A_EDGE_CMD        = 16'h00a0;
    localparam logic [15:0] A_EDGE_RDATA      = 16'h00a4;
    localparam logic [15:0] A_SPIN_RDATA0     = 16'h00a8;

    localparam int CFG_DONE_SET_BIT   = 0;
    localparam int RUN_START_BIT      = 2;
    localparam int SNAPSHOT_LATCH_BIT = 3;
    localparam int RUN_DONE_CLEAR_BIT = 4;
    localparam int CFG_DONE_BIT       = 0;
    localparam int RUN_BUSY_BIT       = 1;
    localparam int RUN_DONE_BIT       = 2;
    localparam int SNAPSHOT_VALID_BIT = 5;
    localparam int ERROR_BIT          = 6;

    localparam int COLS = 20;
    localparam int NODE_IN_UNIT = 8;
    localparam int SNAPSHOT_WIDTH = 320;
    localparam logic [31:0] MAXCUT_EDGE_CFG = 32'h0000_01fd;

    gate_pipeline_env env();
    logic [15:0] pll_cfg;
    string test_name;

`ifdef GATE_SDF
    `include "gate_sdf_setup.svh"
`endif

    function automatic integer flat_index(
        input integer unit_row,
        input integer unit_col,
        input integer node_number
    );
        flat_index = ((unit_row * COLS + unit_col) * NODE_IN_UNIT) +
                     node_number;
    endfunction

    function automatic bit exact_expected(input integer iteration);
        case (iteration)
            1: exact_expected = 1'b1;
            2: exact_expected = 1'b0;
            3: exact_expected = 1'b1;
            4: exact_expected = 1'b1;
            5: exact_expected = 1'b1;
            6: exact_expected = 1'b1;
            7: exact_expected = 1'b1;
            8: exact_expected = 1'b0;
            default: exact_expected = 1'bx;
        endcase
    endfunction

    task automatic check_run_done(input string label);
        logic [31:0] status;
        begin
            env.core_read(A_GLOBAL_STATUS, status);
            if (!status[CFG_DONE_BIT] || !status[RUN_DONE_BIT] ||
                status[RUN_BUSY_BIT] || status[ERROR_BIT])
                $fatal(1, "%s status=%h", label, status);
            env.core_read_check(A_ERROR_STATUS, 32'd0);
        end
    endtask

    task automatic capture_flat_bit(
        input integer index,
        output logic value
    );
        logic [31:0] status;
        logic [31:0] word_value;
        integer page;
        integer within_page;
        integer word_index;
        integer bit_index;
        begin
            page = index / SNAPSHOT_WIDTH;
            within_page = index % SNAPSHOT_WIDTH;
            word_index = within_page / 32;
            bit_index = within_page % 32;
            env.core_write(A_SNAPSHOT_ADDR, page);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << SNAPSHOT_LATCH_BIT));
            env.core_read(A_GLOBAL_STATUS, status);
            if (!status[SNAPSHOT_VALID_BIT] || status[ERROR_BIT])
                $fatal(1, "Snapshot index=%0d page=%0d status=%h",
                       index, page, status);
            env.core_read(A_SPIN_RDATA0 + 4*word_index, word_value);
            if (^word_value === 1'bx)
                $fatal(1, "Unknown snapshot index=%0d word=%h",
                       index, word_value);
            value = word_value[bit_index];
        end
    endtask

    task automatic configure_node(
        input integer unit_row,
        input integer unit_col,
        input integer node_number,
        input bit initial_spin,
        input bit clamp_enable,
        input bit clamp_spin,
        input bit bias_sign,
        input integer bias_probability
    );
        logic [31:0] config;
        logic [31:0] expected;
        begin
            env.core_write(A_UNIT_TARGET, unit_row | (unit_col << 8));
            env.core_write(A_NODE_TARGET,
                           (node_number & 3) | ((node_number >> 2) << 8));
            config = 32'h0000_0007;
            config[8] = initial_spin;
            config[9] = clamp_enable;
            config[10] = clamp_spin;
            config[11] = bias_sign;
            config[18:12] = bias_probability[6:0];
            env.core_write(A_NODE_CFG, config);
            env.core_write(A_NODE_CMD, 32'h0000_0003);

            expected = 32'd0;
            expected[0] = clamp_enable ? clamp_spin : initial_spin;
            expected[1] = clamp_enable;
            expected[2] = clamp_spin;
            expected[3] = bias_sign;
            expected[10:4] = bias_probability[6:0];
            env.core_read_check(A_NODE_RDATA_CFG, expected);
        end
    endtask

    task automatic configure_seed(
        input integer unit_row,
        input integer unit_col,
        input integer seed_number,
        input logic [31:0] seed_value
    );
        begin
            env.core_write(A_UNIT_TARGET, unit_row | (unit_col << 8));
            env.core_write(A_SEED_TARGET, seed_number);
            env.core_write(A_SEED, seed_value);
            env.core_write(A_SEED_CMD, 32'h0000_0003);
            env.core_read_check(A_SEED_RDATA, seed_value);
        end
    endtask

    task automatic configure_edge(
        input integer unit_row,
        input integer unit_col,
        input integer edge_type,
        input integer edge_number
    );
        begin
            env.core_write(A_UNIT_TARGET, unit_row | (unit_col << 8));
            env.core_write(A_EDGE_TARGET,
                           edge_type | (edge_number << 8));
            env.core_write(A_EDGE_CFG, MAXCUT_EDGE_CFG);
            env.core_write(A_EDGE_CMD, 32'h0000_0005);
            env.core_read_check(A_EDGE_RDATA, MAXCUT_EDGE_CFG);
        end
    endtask

    task automatic run_exact;
        logic observed;
        integer iteration;
        begin
            // One free node has a positive bias with code 37. The fixed seed,
            // edge<=/bias< comparison and pipeline random-state offset produce
            // the exact eight-result sequence checked below.
            env.core_write(A_GLOBAL_CFG, 32'h0400_0000);
            env.core_write(A_I0_LEVEL0, 32'h0000_000a);
            env.core_write(A_SWEEP_INTERVAL0, 32'd0);
            configure_node(0, 0, 0, 1'b0, 1'b0, 1'b0,
                           1'b1, 37);
            configure_seed(0, 0, 0, 32'h1357_9bdf);
            env.core_read_check(A_ERROR_STATUS, 32'd0);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));

            for (iteration = 1; iteration <= 8; iteration++) begin
                env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
                check_run_done("exact stochastic run");
                capture_flat_bit(0, observed);
                if (observed !== exact_expected(iteration))
                    $fatal(1,
                        "Exact sequence mismatch iteration=%0d actual=%b expected=%b",
                        iteration, observed, exact_expected(iteration));
                $display("[GATE_EXACT] sweep=%0d spin0=%b PASS",
                         iteration, observed);
                env.core_write(A_GLOBAL_CTRL,
                               32'(1 << RUN_DONE_CLEAR_BIT));
            end
            $display("[TB_GATE_PIPELINE_REGRESSION_EXACT] PASS sequence=10111110 transactions=%0d",
                     env.core_transactions);
        end
    endtask

    task automatic run_crossbank;
        logic owner_right;
        logic neighbor_right;
        logic owner_down;
        logic neighbor_down;
        integer owner_right_index;
        integer neighbor_right_index;
        integer owner_down_index;
        integer neighbor_down_index;
        begin
            owner_right_index = flat_index(4, 4, 4);
            neighbor_right_index = flat_index(4, 5, 4);
            owner_down_index = flat_index(4, 4, 0);
            neighbor_down_index = flat_index(5, 4, 0);

            env.core_write(A_GLOBAL_CFG, 32'h0400_0000);
            env.core_write(A_I0_LEVEL0, 32'h0000_001f);
            env.core_write(A_SWEEP_INTERVAL0, 32'd0);

            // Cell (4,4) is at the lower-right corner of BANK(0,0).
            // Type 4 crosses into BANK(0,1); type 5 crosses into BANK(1,0).
            configure_node(4, 4, 4, 1'b1, 1'b1, 1'b1,
                           1'b0, 0);
            configure_node(4, 5, 4, 1'b1, 1'b0, 1'b0,
                           1'b0, 0);
            configure_node(4, 4, 0, 1'b1, 1'b1, 1'b1,
                           1'b0, 0);
            configure_node(5, 4, 0, 1'b1, 1'b0, 1'b0,
                           1'b0, 0);
            configure_seed(4, 5, 0, 32'h2468_ace1);
            configure_seed(5, 4, 0, 32'h89ab_cdef);
            configure_edge(4, 4, 4, 0);
            configure_edge(4, 4, 5, 0);
            env.core_read_check(A_ERROR_STATUS, 32'd0);

            capture_flat_bit(owner_right_index, owner_right);
            capture_flat_bit(neighbor_right_index, neighbor_right);
            capture_flat_bit(owner_down_index, owner_down);
            capture_flat_bit(neighbor_down_index, neighbor_down);
            if (!owner_right || !neighbor_right ||
                !owner_down || !neighbor_down)
                $fatal(1,
                    "Cross-bank initial state right=%b/%b down=%b/%b",
                    owner_right, neighbor_right, owner_down, neighbor_down);

            env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));
            env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
            check_run_done("cross-bank run");
            capture_flat_bit(owner_right_index, owner_right);
            capture_flat_bit(neighbor_right_index, neighbor_right);
            capture_flat_bit(owner_down_index, owner_down);
            capture_flat_bit(neighbor_down_index, neighbor_down);
            if (!owner_right || neighbor_right ||
                !owner_down || neighbor_down)
                $fatal(1,
                    "Cross-bank MaxCut failed right=%b/%b down=%b/%b",
                    owner_right, neighbor_right, owner_down, neighbor_down);
            $display("[TB_GATE_PIPELINE_REGRESSION_CROSSBANK] PASS right=%0d->%0d down=%0d->%0d transactions=%0d",
                     owner_right_index, neighbor_right_index,
                     owner_down_index, neighbor_down_index,
                     env.core_transactions);
        end
    endtask

    task automatic run_boundary_case(
        input integer sweeps,
        input integer majority
    );
        logic [31:0] config;
        begin
            config = ((majority - 1) << 24) | (sweeps - 1);
            env.core_write(A_GLOBAL_CFG, config);
            env.core_read_check(A_GLOBAL_CFG, config);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
            check_run_done("configuration boundary run");
            env.core_write(A_GLOBAL_CTRL,
                           32'(1 << RUN_DONE_CLEAR_BIT));
            $display("[GATE_BOUNDARY] sweeps=%0d majority=%0d PASS",
                     sweeps, majority);
        end
    endtask

    task automatic run_boundaries;
        begin
            env.core_write(A_GLOBAL_CFG, 32'hffff_ffff);
            env.core_read_check(A_GLOBAL_CFG, 32'h1fff_ffff);
            env.core_write(A_I0_LEVEL0, 32'hffff_ffff);
            env.core_read_check(A_I0_LEVEL0, 32'h1f1f_1f1f);
            env.core_write(A_SWEEP_INTERVAL0, 32'hffff_ffff);
            env.core_read_check(A_SWEEP_INTERVAL0, 32'hffff_ffff);
            env.core_write(A_I0_LEVEL0, 32'h0f0b_0703);
            env.core_write(A_SWEEP_INTERVAL0, 32'h0000_0001);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));

            run_boundary_case(1, 1);
            run_boundary_case(2, 2);
            run_boundary_case(4, 31);
            run_boundary_case(4, 32);
            run_boundary_case(5, 5);
            env.core_read_check(A_ERROR_STATUS, 32'd0);
            $display("[TB_GATE_PIPELINE_REGRESSION_BOUNDARIES] PASS transactions=%0d",
                     env.core_transactions);
        end
    endtask

    task automatic run_recovery;
        logic [31:0] status;
        logic observed;
        integer run_number;
        begin
            env.core_write(A_GLOBAL_CFG, 32'd0);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));

            // A completed run may be acknowledged and followed immediately by
            // another run without resetting or reloading the configuration.
            for (run_number = 1; run_number <= 2; run_number++) begin
                env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
                check_run_done("back-to-back run");
                capture_flat_bit(0, observed);
                if (observed === 1'bx)
                    $fatal(1, "Unknown state after run=%0d", run_number);
                env.core_write(A_GLOBAL_CTRL,
                               32'(1 << RUN_DONE_CLEAR_BIT));
            end

            // 65536 sweeps at majority 32 lasts long enough that the external
            // UART can confirm RUN_BUSY before reset is asserted.
            env.core_write(A_GLOBAL_CFG, 32'h1f00_ffff);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
            env.core_read(A_GLOBAL_STATUS, status);
            if (!status[RUN_BUSY_BIT] || status[RUN_DONE_BIT] ||
                status[ERROR_BIT])
                $fatal(1, "Long run did not remain busy status=%h", status);

            // initialize() starts with a real asynchronous reset edge, then
            // reapplies the external PLL configuration through its UART.
            env.initialize(pll_cfg);
            env.core_read_check(A_GLOBAL_STATUS, 32'd0);
            env.core_read_check(A_ERROR_STATUS, 32'd0);

            env.core_write(A_GLOBAL_CFG, 32'd0);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));
            env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
            check_run_done("post-reset run");
            capture_flat_bit(0, observed);
            if (observed === 1'bx)
                $fatal(1, "Unknown state after reset recovery");
            $display("[TB_GATE_PIPELINE_REGRESSION_RECOVERY] PASS back_to_back=2 mid_run_reset=1 transactions=%0d",
                     env.core_transactions);
        end
    endtask

    initial begin : TEST
        test_name = "exact";
        pll_cfg = 16'h0228;
        void'($value$plusargs("TEST=%s", test_name));
        void'($value$plusargs("PLL_CFG=%h", pll_cfg));
        $display("[GATE_REGRESSION] test=%s pll_cfg=0x%04h",
                 test_name, pll_cfg);
        env.initialize(pll_cfg);
        case (test_name)
            "exact": run_exact();
            "crossbank": run_crossbank();
            "boundaries": run_boundaries();
            "recovery": run_recovery();
            default: $fatal(1,
                "TEST must be exact, crossbank, boundaries or recovery: %s",
                test_name);
        endcase
        $finish;
    end

    initial begin
        #500ms;
        $fatal(1,
            "TB_GATE_PIPELINE_REGRESSION timeout test=%s transactions=%0d",
            test_name, env.core_transactions);
    end
endmodule
