`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
`define TB_GENERATED_PROBLEM_SCORE_SVH
// Generated TSP5 scoring hooks for tb_run_problem.sv.

localparam int unsigned TSP_NUM_CITIES = 5;
localparam int unsigned TSP_OPT_LENGTH_SCALED = 2373137;
localparam int unsigned TSP_OPT_TOL_SCALED = 2;

int unsigned tsp_dist_scaled [TSP_NUM_CITIES][TSP_NUM_CITIES];
int unsigned tsp_opt_tour [TSP_NUM_CITIES];

int unsigned problem_live_best_violation;
int unsigned problem_live_best_length_scaled;
int unsigned problem_live_best_sweep;
int unsigned problem_live_best_cycle;
int unsigned problem_live_final_violation;
int unsigned problem_live_final_length_scaled;
int unsigned problem_live_final_cycle;
int unsigned problem_live_final_broken_chains;
int unsigned problem_live_sample_count;
int unsigned problem_success_count;
int unsigned problem_first_feasible_sweep;
int unsigned problem_first_feasible_cycle;
int unsigned problem_first_optimal_sweep;
int unsigned problem_first_optimal_cycle;
bit problem_live_best_feasible;
bit problem_live_best_success;
bit problem_live_final_feasible;
bit problem_live_final_success;
integer problem_history_fd;

task automatic problem_score_all_runs_init();
    begin
        tsp_dist_scaled[0][0] = 0;
        tsp_dist_scaled[0][1] = 52236;
        tsp_dist_scaled[0][2] = 681672;
        tsp_dist_scaled[0][3] = 545508;
        tsp_dist_scaled[0][4] = 402414;
        tsp_dist_scaled[1][0] = 52236;
        tsp_dist_scaled[1][1] = 0;
        tsp_dist_scaled[1][2] = 652233;
        tsp_dist_scaled[1][3] = 559360;
        tsp_dist_scaled[1][4] = 372396;
        tsp_dist_scaled[2][0] = 681672;
        tsp_dist_scaled[2][1] = 652233;
        tsp_dist_scaled[2][2] = 0;
        tsp_dist_scaled[2][3] = 522698;
        tsp_dist_scaled[2][4] = 880299;
        tsp_dist_scaled[3][0] = 545508;
        tsp_dist_scaled[3][1] = 559360;
        tsp_dist_scaled[3][2] = 522698;
        tsp_dist_scaled[3][3] = 0;
        tsp_dist_scaled[3][4] = 925211;
        tsp_dist_scaled[4][0] = 402414;
        tsp_dist_scaled[4][1] = 372396;
        tsp_dist_scaled[4][2] = 880299;
        tsp_dist_scaled[4][3] = 925211;
        tsp_dist_scaled[4][4] = 0;
        tsp_opt_tour[0] = 0;
        tsp_opt_tour[1] = 1;
        tsp_opt_tour[2] = 4;
        tsp_opt_tour[3] = 2;
        tsp_opt_tour[4] = 3;
        problem_success_count = 0;
    end
endtask

task automatic problem_score_tsp(
    input  bit use_live_spins,
    input  bit print_spins,
    output int unsigned total_violation,
    output bit feasible,
    output bit success,
    output int unsigned tour_length_scaled,
    output int unsigned broken_chain_count
);
    logic logical_spin [PROBLEM_NUM_LOGICAL];
    logic phys_spin;
    int signed chain_sum;
    int signed chain_sum_abs;
    int unsigned chain_len;
    int city_sums [TSP_NUM_CITIES];
    int pos_sums [TSP_NUM_CITIES];
    int tour [TSP_NUM_CITIES];
    int unsigned diff;
    int unsigned logical;
    begin
        broken_chain_count = 0;
        for (int city = 0; city < TSP_NUM_CITIES; city++) begin
            city_sums[city] = 0;
            pos_sums[city] = 0;
            tour[city] = 0;
        end

        for (logical = 0; logical < PROBLEM_NUM_LOGICAL; logical++) begin
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

        for (int city = 0; city < TSP_NUM_CITIES; city++) begin
            for (int pos = 0; pos < TSP_NUM_CITIES; pos++) begin
                logical = city * TSP_NUM_CITIES + pos;
                if (logical_spin[logical]) begin
                    city_sums[city]++;
                    pos_sums[pos]++;
                    tour[pos] = city;
                end
            end
        end

        total_violation = 0;
        for (int city = 0; city < TSP_NUM_CITIES; city++) begin
            total_violation += (city_sums[city] > 1) ? (city_sums[city] - 1) : (1 - city_sums[city]);
            total_violation += (pos_sums[city] > 1) ? (pos_sums[city] - 1) : (1 - pos_sums[city]);
        end
        feasible = (total_violation == 0);

        tour_length_scaled = 0;
        if (feasible) begin
            for (int pos = 0; pos < TSP_NUM_CITIES; pos++) begin
                tour_length_scaled += tsp_dist_scaled[tour[pos]][tour[(pos + 1) % TSP_NUM_CITIES]];
            end
        end
        diff = (tour_length_scaled > TSP_OPT_LENGTH_SCALED) ?
               (tour_length_scaled - TSP_OPT_LENGTH_SCALED) :
               (TSP_OPT_LENGTH_SCALED - tour_length_scaled);
        success = feasible && (diff <= TSP_OPT_TOL_SCALED);

        if (print_spins) begin
            if (feasible) begin
                $display("[RUN_PROBLEM_TSP5] feasible=1 success=%0d violation=%0d tour=%0d,%0d,%0d,%0d,%0d length_scaled=%0d opt_scaled=%0d broken=%0d/%0d",
                         success, total_violation, tour[0], tour[1], tour[2], tour[3], tour[4],
                         tour_length_scaled, TSP_OPT_LENGTH_SCALED,
                         broken_chain_count, PROBLEM_NUM_LOGICAL);
            end else begin
                $display("[RUN_PROBLEM_TSP5] feasible=0 success=0 violation=%0d length_scaled=0 opt_scaled=%0d broken=%0d/%0d",
                         total_violation, TSP_OPT_LENGTH_SCALED,
                         broken_chain_count, PROBLEM_NUM_LOGICAL);
            end
        end
    end
endtask

task automatic problem_score_init(input int unsigned run_idx);
    begin
        problem_live_best_violation = 32'hffffffff;
        problem_live_best_length_scaled = 32'hffffffff;
        problem_live_best_sweep = 0;
        problem_live_best_cycle = 0;
        problem_live_final_violation = 0;
        problem_live_final_length_scaled = 0;
        problem_live_final_cycle = 0;
        problem_live_final_broken_chains = 0;
        problem_live_sample_count = 0;
        problem_first_feasible_sweep = 0;
        problem_first_feasible_cycle = 0;
        problem_first_optimal_sweep = 0;
        problem_first_optimal_cycle = 0;
        problem_live_best_feasible = 1'b0;
        problem_live_best_success = 1'b0;
        problem_live_final_feasible = 1'b0;
        problem_live_final_success = 1'b0;
        problem_history_fd = $fopen($sformatf("sim_run_problem_tsp5_run%0d_history.csv", run_idx), "w");
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "run,sweep,cycles_since_run_start,violation,feasible,success,length_scaled,best_violation,best_feasible,best_success,best_length_scaled,best_sweep,best_cycle,broken_chains,i0_level,round,time");
        end
    end
endtask

task automatic problem_score_record(
    input int unsigned run_idx,
    input int unsigned sweep_idx,
    input int unsigned cycles_since_run_start,
    input bit force_print
);
    int unsigned violation;
    int unsigned length_scaled;
    int unsigned broken_chain_count;
    bit feasible;
    bit success;
    bit improved;
    begin
        problem_score_tsp(1'b1, 1'b0, violation, feasible, success, length_scaled, broken_chain_count);
        improved = (problem_live_sample_count == 0) ||
                   (success && !problem_live_best_success) ||
                   (feasible && !problem_live_best_feasible) ||
                   (feasible && problem_live_best_feasible && (length_scaled < problem_live_best_length_scaled)) ||
                   (!feasible && !problem_live_best_feasible && (violation < problem_live_best_violation));
        if (improved) begin
            problem_live_best_violation = violation;
            problem_live_best_length_scaled = length_scaled;
            problem_live_best_feasible = feasible;
            problem_live_best_success = success;
            problem_live_best_sweep = sweep_idx + 1;
            problem_live_best_cycle = cycles_since_run_start;
        end
        if (feasible && (problem_first_feasible_sweep == 0)) begin
            problem_first_feasible_sweep = sweep_idx + 1;
            problem_first_feasible_cycle = cycles_since_run_start;
        end
        if (success && (problem_first_optimal_sweep == 0)) begin
            problem_first_optimal_sweep = sweep_idx + 1;
            problem_first_optimal_cycle = cycles_since_run_start;
            problem_success_count++;
        end

        problem_live_sample_count++;
        problem_live_final_violation = violation;
        problem_live_final_length_scaled = length_scaled;
        problem_live_final_feasible = feasible;
        problem_live_final_success = success;
        problem_live_final_cycle = cycles_since_run_start;
        problem_live_final_broken_chains = broken_chain_count;

        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                      run_idx, sweep_idx + 1, cycles_since_run_start,
                      violation, feasible, success, length_scaled,
                      problem_live_best_violation, problem_live_best_feasible,
                      problem_live_best_success, problem_live_best_length_scaled,
                      problem_live_best_sweep, problem_live_best_cycle, broken_chain_count,
                      u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                      u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q, $time);
        end
        if (improved || force_print || (((sweep_idx + 1) % PROBLEM_PROGRESS_PRINT_STEP) == 0)) begin
            $display("[RUN_PROBLEM_TSP5_SWEEP] run=%0d sweep=%0d cycles=%0d violation=%0d feasible=%0d success=%0d length_scaled=%0d best_violation=%0d best_feasible=%0d best_success=%0d best_length_scaled=%0d best_sweep=%0d best_cycle=%0d broken=%0d i0=%0d round=%0d",
                     run_idx, sweep_idx + 1, cycles_since_run_start,
                     violation, feasible, success, length_scaled,
                     problem_live_best_violation, problem_live_best_feasible,
                     problem_live_best_success, problem_live_best_length_scaled,
                     problem_live_best_sweep, problem_live_best_cycle, broken_chain_count,
                     u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                     u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
        end
    end
endtask

task automatic problem_score_final(input int unsigned run_idx);
    int unsigned snapshot_violation;
    int unsigned snapshot_length_scaled;
    int unsigned snapshot_broken;
    bit snapshot_feasible;
    bit snapshot_success;
    begin
        problem_score_tsp(1'b0, 1'b1, snapshot_violation, snapshot_feasible,
                          snapshot_success, snapshot_length_scaled, snapshot_broken);
        $display("[RUN_PROBLEM_TSP5_RUN] run=%0d final_violation=%0d final_feasible=%0d final_success=%0d final_length_scaled=%0d final_cycle=%0d best_violation=%0d best_feasible=%0d best_success=%0d best_length_scaled=%0d best_sweep=%0d best_cycle=%0d first_feasible_sweep=%0d first_feasible_cycle=%0d first_optimal_sweep=%0d first_optimal_cycle=%0d opt_length_scaled=%0d",
                 run_idx, snapshot_violation, snapshot_feasible, snapshot_success,
                 snapshot_length_scaled, problem_live_final_cycle,
                 problem_live_best_violation, problem_live_best_feasible,
                 problem_live_best_success, problem_live_best_length_scaled,
                 problem_live_best_sweep, problem_live_best_cycle,
                 problem_first_feasible_sweep, problem_first_feasible_cycle,
                 problem_first_optimal_sweep, problem_first_optimal_cycle,
                 TSP_OPT_LENGTH_SCALED);
        if ((snapshot_violation != problem_live_final_violation) ||
            (snapshot_feasible != problem_live_final_feasible) ||
            (snapshot_success != problem_live_final_success) ||
            (snapshot_length_scaled != problem_live_final_length_scaled) ||
            (snapshot_broken != problem_live_final_broken_chains)) begin
            error_count++;
            $error("[RUN_PROBLEM_TSP5] live/snapshot mismatch");
        end
        if (problem_history_fd != 0) begin
            $fclose(problem_history_fd);
            problem_history_fd = 0;
        end
    end
endtask

function automatic bit problem_score_pass();
    problem_score_pass = (PROBLEM_MIN_PASS_SCORE == 0) ||
                         (problem_success_count >= PROBLEM_MIN_PASS_SCORE);
endfunction

task automatic problem_score_all_runs_summary();
    begin
        $display("[RUN_PROBLEM_TSP5_SUMMARY] success_count=%0d/%0d best_violation=%0d best_feasible=%0d best_success=%0d best_length_scaled=%0d best_sweep=%0d best_cycle=%0d first_feasible_sweep=%0d first_feasible_cycle=%0d first_optimal_sweep=%0d first_optimal_cycle=%0d opt_length_scaled=%0d",
                 problem_success_count, PROBLEM_NUM_SEED_RUNS,
                 problem_live_best_violation, problem_live_best_feasible,
                 problem_live_best_success, problem_live_best_length_scaled,
                 problem_live_best_sweep, problem_live_best_cycle,
                 problem_first_feasible_sweep, problem_first_feasible_cycle,
                 problem_first_optimal_sweep, problem_first_optimal_cycle,
                 TSP_OPT_LENGTH_SCALED);
    end
endtask
`endif
