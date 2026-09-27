`timescale 1ns/1ps

// Lightweight but end-to-end gate-level test. A single Chimera K4,4 cell is
// configured through the external UART, run for 200 sweeps, and read through
// the production snapshot path.
module tb_gate_pipeline_maxcut_lite;
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
    localparam logic [15:0] A_SEED             = 16'h008c;
    localparam logic [15:0] A_SEED_CMD         = 16'h0090;
    localparam logic [15:0] A_SEED_RDATA       = 16'h0094;
    localparam logic [15:0] A_EDGE_TARGET      = 16'h0098;
    localparam logic [15:0] A_EDGE_CFG         = 16'h009c;
    localparam logic [15:0] A_EDGE_CMD         = 16'h00a0;
    localparam logic [15:0] A_EDGE_RDATA       = 16'h00a4;
    localparam logic [15:0] A_SPIN_RDATA0      = 16'h00a8;

    localparam int CFG_DONE_SET_BIT   = 0;
    localparam int RUN_START_BIT      = 2;
    localparam int CFG_DONE_BIT       = 0;
    localparam int RUN_BUSY_BIT       = 1;
    localparam int RUN_DONE_BIT       = 2;
    localparam int SNAPSHOT_LATCH_BIT = 3;
    localparam int SNAPSHOT_VALID_BIT = 5;
    localparam int ERROR_BIT          = 6;

    localparam int N_SPIN = 3200;
    localparam int SNAPSHOT_WIDTH = 320;
    localparam int SNAPSHOT_PAGES = 10;
    localparam int WORDS_PER_PAGE = 10;
    localparam logic [31:0] GLOBAL_CFG_200 = 32'h0400_00c7;
    localparam logic [31:0] MAXCUT_EDGE_CFG = 32'h0000_01fd;

    gate_pipeline_env env();
    logic [N_SPIN-1:0] final_snapshot = '0;
    logic [15:0] pll_cfg;

`ifdef GATE_SDF
    `include "gate_sdf_setup.svh"
`endif

    task automatic configure_node(
        input integer node_number,
        input bit clamped,
        input bit initial_spin
    );
        logic [31:0] target;
        logic [31:0] config;
        logic [31:0] expected;
        begin
            target = (node_number & 3) | ((node_number >> 2) << 8);
            // Bits 0..2 mark init/clamp/bias fields valid. Bias probability is
            // zero, exercising the latest exact-zero bias behavior.
            config = 32'h0000_0007;
            config[8] = initial_spin;
            expected = 32'd0;
            expected[0] = initial_spin;
            if (clamped) begin
                config = config | 32'h0000_0600;
                expected = expected | 32'h0000_0006;
            end
            env.core_write(A_NODE_TARGET, target);
            env.core_write(A_NODE_CFG, config);
            env.core_write(A_NODE_CMD, 32'h0000_0003);
            env.core_read_check(A_NODE_RDATA_CFG, expected);
        end
    endtask

    task automatic configure_seed(
        input integer seed_number,
        input logic [31:0] seed_value
    );
        begin
            env.core_write(A_SEED_TARGET, seed_number);
            env.core_write(A_SEED, seed_value);
            env.core_write(A_SEED_CMD, 32'h0000_0003);
            env.core_read_check(A_SEED_RDATA, seed_value);
        end
    endtask

    task automatic configure_edge(
        input integer left_node,
        input integer right_node
    );
        logic [31:0] target;
        begin
            // Internal K4,4 edge: type selects node 0..3 and number selects
            // node 4..7. This is the same MaxCut encoding used by the passing
            // two-node gate-level test.
            target = left_node | ((right_node - 4) << 8);
            env.core_write(A_EDGE_TARGET, target);
            env.core_write(A_EDGE_CFG, MAXCUT_EDGE_CFG);
            env.core_write(A_EDGE_CMD, 32'h0000_0005);
            env.core_read_check(A_EDGE_RDATA, MAXCUT_EDGE_CFG);
        end
    endtask

    task automatic capture_page0(output logic [31:0] word0);
        logic [31:0] status;
        begin
            env.core_write(A_SNAPSHOT_ADDR, 32'd0);
            env.core_write(A_GLOBAL_CTRL, 32'(1 << SNAPSHOT_LATCH_BIT));
            env.core_read(A_GLOBAL_STATUS, status);
            if (!status[SNAPSHOT_VALID_BIT] || status[ERROR_BIT])
                $fatal(1, "Initial snapshot status=%h", status);
            env.core_read(A_SPIN_RDATA0, word0);
            if (^word0 === 1'bx)
                $fatal(1, "Unknown initial snapshot word=%h", word0);
        end
    endtask

    task automatic capture_all(output logic [N_SPIN-1:0] state);
        logic [31:0] status;
        logic [31:0] word_value;
        integer page;
        integer word_index;
        integer base;
        begin
            state = '0;
            for (page = 0; page < SNAPSHOT_PAGES; page++) begin
                env.core_write(A_SNAPSHOT_ADDR, page);
                env.core_write(A_GLOBAL_CTRL,
                               32'(1 << SNAPSHOT_LATCH_BIT));
                env.core_read(A_GLOBAL_STATUS, status);
                if (!status[CFG_DONE_BIT] || !status[RUN_DONE_BIT] ||
                    status[RUN_BUSY_BIT] || !status[SNAPSHOT_VALID_BIT] ||
                    status[ERROR_BIT])
                    $fatal(1, "Final snapshot page=%0d status=%h",
                           page, status);
                for (word_index = 0; word_index < WORDS_PER_PAGE;
                     word_index++) begin
                    env.core_read(A_SPIN_RDATA0 + 4*word_index, word_value);
                    if (^word_value === 1'bx)
                        $fatal(1,
                            "Unknown final snapshot page=%0d word=%0d value=%h",
                            page, word_index, word_value);
                    base = page*SNAPSHOT_WIDTH + word_index*32;
                    state[base +: 32] = word_value;
                end
                $display("[GATE_MAXCUT_LITE_SNAPSHOT] page=%0d/%0d PASS",
                         page+1, SNAPSHOT_PAGES);
            end
        end
    endtask

    function automatic integer k44_score(input logic [7:0] state);
        integer score;
        begin
            score = 0;
            for (int left_node = 0; left_node < 4; left_node++)
                for (int right_node = 4; right_node < 8; right_node++)
                    if (state[left_node] != state[right_node])
                        score++;
            return score;
        end
    endfunction

    initial begin : TEST
        logic [31:0] initial_word0;
        logic [31:0] status;
        logic [31:0] errors;
        integer score;
        integer result_file;
        integer unused;

        pll_cfg = 16'h0228;
        unused = $value$plusargs("PLL_CFG=%h", pll_cfg);
        $display("[GATE_MAXCUT_LITE] K4,4 nodes=8 edges=16 sweeps=200 pll_cfg=0x%04h",
                 pll_cfg);
        env.initialize(pll_cfg);

        // 200 sweeps, majority five. A single maximum-I0 stage spans all 200.
        env.core_write(A_GLOBAL_CFG, GLOBAL_CFG_200);
        env.core_read_check(A_GLOBAL_CFG, GLOBAL_CFG_200);
        env.core_write(A_I0_LEVEL0, 32'h0000_001f);
        env.core_read_check(A_I0_LEVEL0, 32'h0000_001f);
        env.core_write(A_SWEEP_INTERVAL0, 32'h0000_00c7);
        env.core_read_check(A_SWEEP_INTERVAL0, 32'h0000_00c7);

        // Unit (0,0): clamp nodes 0..3 high and start free nodes 4..7 high.
        env.core_write(A_UNIT_TARGET, 32'd0);
        env.core_read_check(A_UNIT_TARGET, 32'd0);
        for (int node_number = 0; node_number < 4; node_number++)
            configure_node(node_number, 1'b1, 1'b1);
        for (int node_number = 4; node_number < 8; node_number++)
            configure_node(node_number, 1'b0, 1'b1);

        configure_seed(0, 32'h1357_9bdf);
        configure_seed(1, 32'h2468_ace1);
        configure_seed(2, 32'h1f2e_3d4c);
        configure_seed(3, 32'h89ab_cdef);

        for (int left_node = 0; left_node < 4; left_node++)
            for (int right_node = 4; right_node < 8; right_node++)
                configure_edge(left_node, right_node);
        env.core_read_check(A_ERROR_STATUS, 32'd0);
        $display("[GATE_MAXCUT_LITE_CONFIG] PASS transactions=%0d",
                 env.core_transactions);

        capture_page0(initial_word0);
        if (initial_word0[7:0] !== 8'hff)
            $fatal(1, "K4,4 initial state mismatch word0=%h", initial_word0);

        env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));
        env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
        env.core_read(A_GLOBAL_STATUS, status);
        if (!status[CFG_DONE_BIT] || !status[RUN_DONE_BIT] ||
            status[RUN_BUSY_BIT] || status[ERROR_BIT])
            $fatal(1, "K4,4 post-run status=%h", status);

        capture_all(final_snapshot);
        score = k44_score(final_snapshot[7:0]);
        if (final_snapshot[7:0] !== 8'h0f || score != 16)
            $fatal(1,
                "K4,4 MaxCut mismatch initial=%h final=%h score=%0d expected=16",
                initial_word0[7:0], final_snapshot[7:0], score);
        env.core_read(A_ERROR_STATUS, errors);
        if (errors !== 32'd0)
            $fatal(1, "K4,4 error status=%h", errors);

        result_file = $fopen("gate_maxcut_lite_result.txt", "w");
        if (!result_file)
            $fatal(1, "Cannot create gate_maxcut_lite_result.txt");
        $fdisplay(result_file,
                  "problem=K4,4 sweeps=200 majority=5 initial=%02h final=%02h score=%0d target=16 transactions=%0d",
                  initial_word0[7:0], final_snapshot[7:0], score,
                  env.core_transactions);
        $fdisplay(result_file, "final_physical_spins=%h", final_snapshot);
        $fclose(result_file);

        $display("[TB_GATE_PIPELINE_MAXCUT_LITE] PASS initial=%02h final=%02h score=%0d/16 transactions=%0d",
                 initial_word0[7:0], final_snapshot[7:0], score,
                 env.core_transactions);
        $finish;
    end

    initial begin
        #500ms;
        $fatal(1, "TB_GATE_PIPELINE_MAXCUT_LITE timeout transactions=%0d",
               env.core_transactions);
    end
endmodule
