`timescale 1ns/1ps

// Full external-UART gate-level run of the generated native Chimera MaxCut
// problem. Every node, LFSR seed and physical edge is configured and read back
// through the production serial protocol before the 200-sweep run.
module tb_gate_pipeline_maxcut;
    `include "problem.svh"

    localparam logic [15:0] A_GLOBAL_CTRL    = 16'h0000;
    localparam logic [15:0] A_GLOBAL_STATUS  = 16'h0008;
    localparam logic [15:0] A_ERROR_STATUS   = 16'h000c;
    localparam logic [15:0] A_SNAPSHOT_ADDR  = 16'h0010;
    localparam logic [15:0] A_SPIN_RDATA0    = 16'h00a8;
    localparam int CFG_DONE_SET_BIT   = 0;
    localparam int RUN_START_BIT      = 2;
    localparam int SNAPSHOT_LATCH_BIT = 3;
    localparam int CFG_DONE_BIT       = 0;
    localparam int RUN_BUSY_BIT       = 1;
    localparam int RUN_DONE_BIT       = 2;
    localparam int SNAPSHOT_VALID_BIT = 5;
    localparam int ERROR_BIT          = 6;
    localparam int SNAPSHOT_WIDTH = 320;
    localparam int WORDS_PER_PAGE = 10;
    localparam int SNAPSHOT_PAGES = 10;

    gate_pipeline_env env();
    logic [55:0] program_mem [P_COMMANDS];
    logic initial_bits [P_N];
    integer chain_start [P_CHAINS+1];
    integer chain_nodes [P_CHAIN_NODES];
    integer graph_a [(P_EDGES>0)?P_EDGES:1];
    integer graph_b [(P_EDGES>0)?P_EDGES:1];
    integer graph_w [(P_EDGES>0)?P_EDGES:1];
    logic [P_CHAINS-1:0] decoded;
    logic [P_N-1:0] initial_snapshot = '0;
    logic [P_N-1:0] final_snapshot = '0;
    logic [15:0] pll_cfg;
    string data_dir;

`ifdef GATE_SDF
    `include "gate_sdf_setup.svh"
`endif

    function automatic string required_file(input string name);
        string path;
        integer handle;
        begin
            path = $sformatf("%s/%s", data_dir, name);
            handle = $fopen(path, "r");
            if (!handle)
                $fatal(1, "Missing generated input: %s", path);
            $fclose(handle);
            return path;
        end
    endfunction

    task automatic capture_snapshot(output logic [P_N-1:0] state);
        logic [31:0] status;
        logic [31:0] word_value;
        integer page;
        integer word_idx;
        integer base;
        begin
            state = '0;
            for (page = 0; page < SNAPSHOT_PAGES; page++) begin
                env.core_write(A_SNAPSHOT_ADDR, page);
                env.core_write(A_GLOBAL_CTRL,
                               32'(1 << SNAPSHOT_LATCH_BIT));
                env.core_read(A_GLOBAL_STATUS, status);
                if (!status[SNAPSHOT_VALID_BIT] || status[ERROR_BIT])
                    $fatal(1, "Snapshot page=%0d status=%h", page, status);
                for (word_idx = 0; word_idx < WORDS_PER_PAGE; word_idx++) begin
                    env.core_read(A_SPIN_RDATA0 + 4*word_idx, word_value);
                    if (^word_value === 1'bx)
                        $fatal(1, "Unknown snapshot page=%0d word=%0d value=%h",
                               page, word_idx, word_value);
                    base = page*SNAPSHOT_WIDTH + word_idx*32;
                    state[base +: 32] = word_value;
                end
                $display("[GATE_MAXCUT_SNAPSHOT] page=%0d/%0d time=%0t",
                         page+1, SNAPSHOT_PAGES, $time);
            end
        end
    endtask

    task automatic evaluate(
        input logic [P_N-1:0] state,
        output longint signed value,
        output integer broken,
        output integer ties
    );
        integer total;
        bit differs;
        begin
            value = 0;
            broken = 0;
            ties = 0;
            if ((^state) === 1'bx)
                $fatal(1, "Unknown spin in MaxCut state");
            for (int v = 0; v < P_CHAINS; v++) begin
                total = 0;
                differs = 0;
                for (int k = chain_start[v]; k < chain_start[v+1]; k++) begin
                    total += state[chain_nodes[k]] ? 1 : -1;
                    if (state[chain_nodes[k]] !=
                        state[chain_nodes[chain_start[v]]])
                        differs = 1;
                end
                decoded[v] = (total >= 0);
                if (total == 0)
                    ties++;
                if (differs)
                    broken++;
            end
            for (int e = 0; e < P_EDGES; e++)
                if (decoded[graph_a[e]] != decoded[graph_b[e]])
                    value += graph_w[e];
        end
    endtask

    initial begin : TEST
        logic [31:0] status;
        logic [31:0] errors;
        logic [P_N-1:0] expected_initial;
        longint signed initial_score;
        longint signed final_score;
        integer initial_broken;
        integer initial_ties;
        integer final_broken;
        integer final_ties;
        integer result_file;
        integer unused;

        data_dir = ".";
        pll_cfg = 16'h0228;
        unused = $value$plusargs("DATA_DIR=%s", data_dir);
        unused = $value$plusargs("PLL_CFG=%h", pll_cfg);
        if (P_CASE != "native_cut_n0448_s201" || P_N != 3200 ||
            P_SWEEPS != 200 || P_RUNS != 1 || P_MAJORITY != 5 ||
            P_SAT != 0 || SNAPSHOT_PAGES*SNAPSHOT_WIDTH != P_N)
            $fatal(1, "Unexpected generated MaxCut parameters");

        $readmemh(required_file("config_0.mem"), program_mem);
        $readmemh(required_file("initial_0.mem"), initial_bits);
        $readmemh(required_file("chain_start.mem"), chain_start);
        $readmemh(required_file("chain_nodes.mem"), chain_nodes);
        $readmemh(required_file("graph_a.mem"), graph_a);
        $readmemh(required_file("graph_b.mem"), graph_b);
        $readmemh(required_file("graph_w.mem"), graph_w);
        for (int v = 0; v < P_N; v++)
            expected_initial[v] = initial_bits[v];

        $display("[GATE_MAXCUT] case=%s logical_nodes=%0d logical_edges=%0d physical_pbits=%0d commands=%0d sweeps=%0d majority=%0d target=%0d",
                 P_CASE, P_VARIABLES, P_EDGES, P_N, P_COMMANDS,
                 P_SWEEPS, P_MAJORITY, P_TARGET);
        env.initialize(pll_cfg);

        for (int k = 0; k < P_COMMANDS; k++) begin
            case (program_mem[k][55:48])
                8'd1: env.core_write(program_mem[k][47:32],
                                     program_mem[k][31:0]);
                8'd2: env.core_read_check(program_mem[k][47:32],
                                          program_mem[k][31:0]);
                default: $fatal(1,
                    "Invalid configuration instruction index=%0d value=%h",
                    k, program_mem[k]);
            endcase
            if ((k+1) % 1000 == 0 || k+1 == P_COMMANDS)
                $display("[GATE_MAXCUT_CONFIG] completed=%0d/%0d transactions=%0d time=%0t",
                         k+1, P_COMMANDS, env.core_transactions, $time);
        end

        // Confirm that all 3200 individually programmed initial spins reached
        // the synthesized array before starting the anneal.
        capture_snapshot(initial_snapshot);
        if (initial_snapshot !== expected_initial)
            $fatal(1, "Initial 3200-bit snapshot differs from generated state");
        evaluate(initial_snapshot, initial_score, initial_broken, initial_ties);
        $display("[GATE_MAXCUT_INITIAL] score=%0d broken=%0d ties=%0d",
                 initial_score, initial_broken, initial_ties);

        env.core_write(A_GLOBAL_CTRL, 32'(1 << CFG_DONE_SET_BIT));
        env.core_write(A_GLOBAL_CTRL, 32'(1 << RUN_START_BIT));
        env.core_read(A_GLOBAL_STATUS, status);
        if (!status[CFG_DONE_BIT] || !status[RUN_DONE_BIT] ||
            status[RUN_BUSY_BIT] || status[ERROR_BIT])
            $fatal(1, "Unexpected post-run status=%h", status);

        capture_snapshot(final_snapshot);
        evaluate(final_snapshot, final_score, final_broken, final_ties);
        env.core_read(A_ERROR_STATUS, errors);
        if (errors !== 32'd0)
            $fatal(1, "MaxCut run error status=%h", errors);

        result_file = $fopen("gate_maxcut_result.txt", "w");
        if (!result_file)
            $fatal(1, "Cannot create gate_maxcut_result.txt");
        $fdisplay(result_file,
                  "case=%s sweeps=%0d majority=%0d target=%0d initial_score=%0d final_score=%0d initial_broken=%0d final_broken=%0d initial_ties=%0d final_ties=%0d transactions=%0d",
                  P_CASE, P_SWEEPS, P_MAJORITY, P_TARGET,
                  initial_score, final_score, initial_broken, final_broken,
                  initial_ties, final_ties, env.core_transactions);
        $fdisplay(result_file, "final_physical_spins=%h", final_snapshot);
        $fdisplay(result_file, "final_logical_spins=%h", decoded);
        $fclose(result_file);

        $display("[GATE_MAXCUT_RESULT] initial=%0d final=%0d target=%0d broken=%0d ties=%0d transactions=%0d",
                 initial_score, final_score, P_TARGET, final_broken,
                 final_ties, env.core_transactions);
        $display("[TB_GATE_PIPELINE_MAXCUT] PASS configuration/run/snapshot/score checks; optimization target reported separately");
        $finish;
    end

    initial begin
        #20s;
        $fatal(1, "TB_GATE_PIPELINE_MAXCUT timeout transactions=%0d",
               env.core_transactions);
    end
endmodule
