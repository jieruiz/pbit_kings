`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
`define TB_GENERATED_PROBLEM_SCORE_SVH
// Generated MaxCut scoring hooks for tb_run_problem.sv.

int unsigned problem_live_best_score;
int unsigned problem_live_best_sweep;
int unsigned problem_live_best_cycle;
int unsigned problem_live_best_broken_chains;
int unsigned problem_live_final_score;
int unsigned problem_live_final_cycle;
int unsigned problem_live_final_broken_chains;
int unsigned problem_live_sample_count;
integer problem_history_fd;

task automatic problem_score_all_runs_init();
    begin
    end
endtask

task automatic problem_score_spins(
    input  bit use_live_spins,
    input  bit print_spins,
    output int unsigned score,
    output int unsigned broken_chain_count
);
    logic logical_spin [PROBLEM_NUM_LOGICAL];
    logic phys_spin;
    int signed chain_sum;
    int signed chain_sum_abs;
    int unsigned chain_len;
    begin
        broken_chain_count = 0;
        for (int logical = 0; logical < PROBLEM_NUM_LOGICAL; logical++) begin
            chain_sum = 0;
            for (int p = problem_chain_start[logical]; p < problem_chain_start[logical + 1]; p++) begin
                phys_spin = use_live_spins ?
                            physical_spin_live(problem_chain_phys_idx[p]) :
                            physical_spin_snapshot(problem_chain_phys_idx[p]);
                chain_sum += phys_spin ? 1 : -1;
            end
            chain_len = problem_chain_start[logical + 1] - problem_chain_start[logical];
            chain_sum_abs = (chain_sum < 0) ? -chain_sum : chain_sum;
            if (chain_sum_abs != chain_len) begin
                broken_chain_count++;
            end
            logical_spin[logical] = (chain_sum >= 0);
        end

        score = 0;
        for (int edge_idx = 0; edge_idx < PROBLEM_NUM_LOGICAL_EDGES; edge_idx++) begin
            if (logical_spin[problem_logical_edge_a[edge_idx]] != logical_spin[problem_logical_edge_b[edge_idx]]) begin
                score += problem_logical_edge_weight[edge_idx];
            end
        end

        if (print_spins) begin
            $display("[RUN_PROBLEM_MAXCUT] broken_chains=%0d/%0d", broken_chain_count, PROBLEM_NUM_LOGICAL);
        end
    end
endtask

task automatic problem_score_init(input int unsigned run_idx);
    begin
        problem_live_best_score = 0;
        problem_live_best_sweep = 0;
        problem_live_best_cycle = 0;
        problem_live_best_broken_chains = 0;
        problem_live_final_score = 0;
        problem_live_final_cycle = 0;
        problem_live_final_broken_chains = 0;
        problem_live_sample_count = 0;
        problem_history_fd = $fopen($sformatf("sim_run_problem_maxcut_run%0d_history.csv", run_idx), "w");
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "run,sweep,cycles_since_run_start,current_score,best_score,best_sweep,best_cycle,broken_chains,best_broken_chains,i0_level,round,time");
        end
    end
endtask

task automatic problem_score_record(
    input int unsigned run_idx,
    input int unsigned sweep_idx,
    input int unsigned cycles_since_run_start,
    input bit force_print
);
    int unsigned score;
    int unsigned broken_chain_count;
    bit improved;
    begin
        problem_score_spins(1'b1, 1'b0, score, broken_chain_count);
        improved = (problem_live_sample_count == 0) || (score > problem_live_best_score);
        if (improved) begin
            problem_live_best_score = score;
            problem_live_best_sweep = sweep_idx + 1;
            problem_live_best_cycle = cycles_since_run_start;
            problem_live_best_broken_chains = broken_chain_count;
        end
        problem_live_sample_count++;
        problem_live_final_score = score;
        problem_live_final_cycle = cycles_since_run_start;
        problem_live_final_broken_chains = broken_chain_count;
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                      run_idx, sweep_idx + 1, cycles_since_run_start,
                      score, problem_live_best_score,
                      problem_live_best_sweep, problem_live_best_cycle, broken_chain_count,
                      problem_live_best_broken_chains,
                      u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                      u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q, $time);
        end
        if (improved || force_print || (((sweep_idx + 1) % PROBLEM_PROGRESS_PRINT_STEP) == 0)) begin
            $display("[RUN_PROBLEM_MAXCUT_SWEEP] run=%0d sweep=%0d cycles=%0d score=%0d best=%0d best_sweep=%0d best_cycle=%0d broken=%0d i0=%0d round=%0d",
                     run_idx, sweep_idx + 1, cycles_since_run_start,
                     score, problem_live_best_score,
                     problem_live_best_sweep, problem_live_best_cycle, broken_chain_count,
                     u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                     u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
        end
    end
endtask

task automatic problem_score_final(input int unsigned run_idx);
    int unsigned snapshot_score;
    int unsigned snapshot_broken;
    begin
        problem_score_spins(1'b0, 1'b1, snapshot_score, snapshot_broken);
        $display("[RUN_PROBLEM_MAXCUT_RUN] run=%0d final_score=%0d final_cycle=%0d best_score=%0d best_sweep=%0d best_cycle=%0d min_pass=%0d total_weight=%0d",
                 run_idx, snapshot_score, problem_live_final_cycle,
                 problem_live_best_score, problem_live_best_sweep,
                 problem_live_best_cycle, PROBLEM_MIN_PASS_SCORE,
                 PROBLEM_TOTAL_LOGICAL_WEIGHT);
        if (snapshot_score != problem_live_final_score) begin
            error_count++;
            $error("[RUN_PROBLEM_MAXCUT] live/snapshot score mismatch: live=%0d snapshot=%0d",
                   problem_live_final_score, snapshot_score);
        end
        if (snapshot_broken != problem_live_final_broken_chains) begin
            error_count++;
            $error("[RUN_PROBLEM_MAXCUT] live/snapshot broken-chain mismatch: live=%0d snapshot=%0d",
                   problem_live_final_broken_chains, snapshot_broken);
        end
        if (problem_history_fd != 0) begin
            $fclose(problem_history_fd);
            problem_history_fd = 0;
        end
    end
endtask

function automatic bit problem_score_pass();
    problem_score_pass = (problem_live_best_score >= PROBLEM_MIN_PASS_SCORE);
endfunction

task automatic problem_score_all_runs_summary();
    begin
        $display("[RUN_PROBLEM_MAXCUT_SUMMARY] best_score=%0d best_sweep=%0d best_cycle=%0d min_pass=%0d",
                 problem_live_best_score, problem_live_best_sweep,
                 problem_live_best_cycle, PROBLEM_MIN_PASS_SCORE);
    end
endtask
`endif
