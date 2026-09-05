#!/usr/bin/env python3
"""Generate a TSP5-on-40x40-King's-graph Verilog simulation case.

The source exploration script uses numpy/networkx/minorminer to build a TSP5
QUBO and embedding. This generator intentionally uses only the Python standard
library: it consumes the saved mapping/J/bias/distance files and emits the
standard tb_run_problem.sv include files.
"""

import argparse
import json
import math
import sys
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import gen_problem as gp  # noqa: E402


EDGE_RANDOM_MAX_CODE = 127
TSP_NUM_CITIES = 5
TSP_NUM_LOGICAL = TSP_NUM_CITIES * TSP_NUM_CITIES
DIST_SCALE = 1000000
OPT_TOL_SCALED = 2


def load_matrix(path, size=None):
    rows = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if raw:
            rows.append([float(x) for x in raw.split()])
    if size is not None:
        if len(rows) != size or any(len(row) != size for row in rows):
            raise ValueError("{} must be {}x{}".format(path, size, size))
    return rows


def load_vector(path, size):
    values = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if raw:
            values.extend(float(x) for x in raw.split())
    if len(values) != size:
        raise ValueError("{} must contain {} values".format(path, size))
    return values


def load_mapping(path, num_logical):
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    mapping = {int(k): [int(q) for q in v] for k, v in raw.items()}
    missing = sorted(set(range(num_logical)) - set(mapping))
    if missing:
        raise ValueError("mapping missing logical p-bits: {}".format(missing))
    return {logical: mapping[logical] for logical in range(num_logical)}


def normalize_signed_coupling(J):
    max_abs = 0.0
    for row in J:
        for value in row:
            max_abs = max(max_abs, abs(value))
    if max_abs <= 0:
        raise ValueError("all TSP couplings are zero")
    return max_abs


def quantize_probability(value):
    value = max(0.0, min(1.0, float(value)))
    return int(round(value * EDGE_RANDOM_MAX_CODE))


def rtl_edge_sign_from_solver_sign(sign_value):
    # The source sampler uses h = -sum(J*s_j) + bias. RTL directly sums
    # configured edge contributions, so solver J signs are inverted here.
    return 0 if sign_value > 0 else 1


def build_physical_problem(J, logical_bias, mapping, kings_cols, bias_placement):
    logical_scale = normalize_signed_coupling(J)
    physical_nodes = sorted({q for chain in mapping.values() for q in chain})
    phys_to_idx = {q: idx for idx, q in enumerate(physical_nodes)}
    n_phys = len(physical_nodes)
    p_phys = [[0.0 for _ in range(n_phys)] for _ in range(n_phys)]
    sign_phys = [[0 for _ in range(n_phys)] for _ in range(n_phys)]
    missing_logical_edges = []

    for a in range(len(J)):
        for b in range(a + 1, len(J)):
            if J[a][b] == 0:
                continue
            p_edge = abs(J[a][b]) / logical_scale
            couplers = []
            for qa in mapping[a]:
                for qb in mapping[b]:
                    if gp.are_kings_neighbors(qa, qb, kings_cols):
                        couplers.append((qa, qb))
            if not couplers:
                missing_logical_edges.append((a, b))
                continue
            p_each = p_edge / len(couplers)
            rtl_sign = rtl_edge_sign_from_solver_sign(J[a][b])
            for qa, qb in couplers:
                ia = phys_to_idx[qa]
                ib = phys_to_idx[qb]
                if p_each > p_phys[ia][ib]:
                    p_phys[ia][ib] = p_each
                    p_phys[ib][ia] = p_each
                sign_phys[ia][ib] = rtl_sign
                sign_phys[ib][ia] = rtl_sign

    for chain in mapping.values():
        for idx_a in range(len(chain)):
            for idx_b in range(idx_a + 1, len(chain)):
                qa = chain[idx_a]
                qb = chain[idx_b]
                if gp.are_kings_neighbors(qa, qb, kings_cols):
                    ia = phys_to_idx[qa]
                    ib = phys_to_idx[qb]
                    p_phys[ia][ib] = 1.0
                    p_phys[ib][ia] = 1.0
                    # Chain couplers must be ferromagnetic in RTL.
                    sign_phys[ia][ib] = 1
                    sign_phys[ib][ia] = 1

    chain_lengths = {logical: len(chain) for logical, chain in mapping.items()}
    phys_to_logical = {}
    for logical, chain in mapping.items():
        for q in chain:
            phys_to_logical[q] = logical

    bias_raw = []
    for q in physical_nodes:
        logical = phys_to_logical[q]
        bias_value = logical_bias[logical]
        if bias_placement == "distribute":
            bias_value = bias_value / chain_lengths[logical]
        bias_raw.append(bias_value)

    max_edge_abs = max((p_phys[i][j] for i in range(n_phys) for j in range(n_phys)), default=0.0)
    max_bias_abs = max((abs(v) for v in bias_raw), default=0.0)
    global_scale = max(max_edge_abs, max_bias_abs, 1.0e-12)

    config_edges = []
    max_degree = 0
    for ia, qa in enumerate(physical_nodes):
        degree = 0
        for ib in range(ia + 1, n_phys):
            if p_phys[ia][ib] <= 0:
                continue
            py_code = quantize_probability(p_phys[ia][ib] / global_scale)
            if py_code <= 0:
                continue
            degree += 1
            r1, c1 = gp.kings_coord(qa, kings_cols)
            r2, c2 = gp.kings_coord(physical_nodes[ib], kings_cols)
            edge_type, row, col = gp.edge_target_from_coords(r1, c1, r2, c2)
            config_edges.append((edge_type, row, col, gp.rtl_prob_code_from_python_code(py_code), sign_phys[ia][ib]))
        max_degree = max(max_degree, degree)

    degrees = [0 for _ in physical_nodes]
    for edge_type, row, col, prob, sign in config_edges:
        _ = edge_type, prob, sign
        if edge_type == "EDGE_TYPE_EDGE_H":
            qa = row * kings_cols + col
            qb = row * kings_cols + col + 1
        elif edge_type == "EDGE_TYPE_EDGE_V":
            qa = row * kings_cols + col
            qb = (row + 1) * kings_cols + col
        elif edge_type == "EDGE_TYPE_EDGE_DSE":
            qa = row * kings_cols + col
            qb = (row + 1) * kings_cols + col + 1
        else:
            qa = row * kings_cols + col
            qb = (row + 1) * kings_cols + col - 1
        degrees[phys_to_idx[qa]] += 1
        degrees[phys_to_idx[qb]] += 1
    max_degree = max(degrees) if degrees else 0

    if max_degree > 8:
        raise ValueError("physical max degree {} exceeds RTL limit 8".format(max_degree))

    bias_prob = []
    bias_sign = []
    for value in bias_raw:
        py_code = quantize_probability(abs(value) / global_scale)
        bias_prob.append(gp.rtl_prob_code_from_python_code(py_code))
        bias_sign.append(1 if value >= 0 else 0)

    return {
        "physical_nodes": physical_nodes,
        "phys_to_idx": phys_to_idx,
        "config_edges": config_edges,
        "bias_prob": bias_prob,
        "bias_sign": bias_sign,
        "missing_logical_edges": missing_logical_edges,
        "max_degree": max_degree,
        "global_scale": global_scale,
        "logical_scale": logical_scale,
    }


def scaled_distance_matrix(dist):
    return [[int(round(value * DIST_SCALE)) for value in row] for row in dist]


def tsp_score_template(dist_scaled, opt_length_scaled, opt_tour):
    dist_lines = []
    for r, row in enumerate(dist_scaled):
        for c, value in enumerate(row):
            dist_lines.append("        tsp_dist_scaled[{}][{}] = {};".format(r, c, value))
    opt_tour_values = ", ".join(str(int(x)) for x in opt_tour)
    return r'''`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
`define TB_GENERATED_PROBLEM_SCORE_SVH
// Generated TSP5 scoring hooks for tb_run_problem.sv.

localparam int unsigned TSP_NUM_CITIES = 5;
localparam int unsigned TSP_OPT_LENGTH_SCALED = __OPT_LENGTH__;
localparam int unsigned TSP_OPT_TOL_SCALED = __OPT_TOL__;

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
__DIST_ASSIGN__
__TOUR_ASSIGN__
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
'''.replace("__OPT_LENGTH__", str(opt_length_scaled)).replace(
        "__OPT_TOL__", str(OPT_TOL_SCALED)
    ).replace(
        "__DIST_ASSIGN__", "\n".join(dist_lines)
    ).replace(
        "__TOUR_ASSIGN__",
        "\n".join(
            "        tsp_opt_tour[{}] = {};".format(idx, city)
            for idx, city in enumerate(opt_tour)
        )
    )


def build_problem(spec_path, spec):
    inputs = spec["inputs"]
    hw = spec.get("hardware", {})
    run = spec.get("run", {})
    kings_rows = int(hw.get("kings_rows", 40))
    kings_cols = int(hw.get("kings_cols", 40))
    rtl_rows = int(hw.get("rtl_rows", kings_rows))
    rtl_cols = int(hw.get("rtl_cols", 80))
    seed_rows = (rtl_rows + 1) // 2
    seed_cols = (rtl_cols + 1) // 2
    bias_placement = spec.get("problem", {}).get("bias_placement", "distribute")
    if bias_placement not in ("distribute", "replicate"):
        raise ValueError("bias_placement must be distribute or replicate")

    mapping = load_mapping(gp.resolve_path(spec_path, inputs["mapping"]), TSP_NUM_LOGICAL)
    dist = load_matrix(gp.resolve_path(spec_path, inputs["distance"]), TSP_NUM_CITIES)
    J = load_matrix(gp.resolve_path(spec_path, inputs["j"]), TSP_NUM_LOGICAL)
    logical_bias = load_vector(gp.resolve_path(spec_path, inputs["bias"]), TSP_NUM_LOGICAL)
    problem_meta = gp.load_json(gp.resolve_path(spec_path, inputs["problem"]))
    opt_tour = [int(x) for x in problem_meta["exact_opt_tour"]]
    opt_length_scaled = int(round(float(problem_meta["exact_opt_length"]) * DIST_SCALE))

    physical = build_physical_problem(J, logical_bias, mapping, kings_cols, bias_placement)
    if physical["missing_logical_edges"]:
        raise ValueError("embedding missing logical couplers: {}".format(physical["missing_logical_edges"][:10]))

    num_runs = int(run.get("num_runs", 1))
    tile_seeds, init_spins, global_seeds = gp.build_maxcut_node_data(
        physical["physical_nodes"],
        num_runs,
        int(run.get("seed_master_start", run.get("seed_master", 24680))),
        int(run.get("seed_master_step", 1)),
        int(run.get("run_seed", 0)),
        seed_rows,
        seed_cols,
    )
    i0_levels = gp.build_i0_levels(run, spec_path)
    num_sweeps, intervals = gp.build_intervals(run, len(i0_levels))
    chain_start, chain_phys_idx = gp.chain_arrays(mapping, physical["phys_to_idx"])
    max_flat = max((gp.kings_coord(q, kings_cols)[0] * rtl_cols) + gp.kings_coord(q, kings_cols)[1]
                   for q in physical["physical_nodes"])
    snapshot_width = int(spec.get("snapshot_width", gp.RTL_SNAPSHOT_WIDTH))
    snapshot_pages = int(math.ceil((max_flat + 1) / float(snapshot_width)))

    problem = {
        "name": spec["name"],
        "kind": "maxcut",
        "num_logical": TSP_NUM_LOGICAL,
        "num_variables": TSP_NUM_LOGICAL,
        "num_clauses": 0,
        "lits_per_clause": 0,
        "kings_rows": kings_rows,
        "kings_cols": kings_cols,
        "rtl_rows": rtl_rows,
        "rtl_cols": rtl_cols,
        "seed_rows": seed_rows,
        "seed_cols": seed_cols,
        "physical_nodes": physical["physical_nodes"],
        "phys_to_idx": physical["phys_to_idx"],
        "config_edges": physical["config_edges"],
        "clear_edges": gp.build_clear_edges(kings_rows, rtl_cols),
        "tile_seeds": tile_seeds,
        "init_spins": init_spins,
        "global_seeds": global_seeds,
        "bias_prob": physical["bias_prob"],
        "bias_sign": physical["bias_sign"],
        "chain_start": chain_start,
        "chain_phys_idx": chain_phys_idx,
        "logical_edges": [],
        "logical_edge_signs": [],
        "target_spins": [1 for _ in range(TSP_NUM_LOGICAL)],
        "clauses": [],
        "i0_levels": i0_levels,
        "intervals": intervals,
        "num_sweeps": num_sweeps,
        "num_majority": int(run.get("num_majority", 3)),
        "num_runs": num_runs,
        "progress_print_step": int(run.get("progress_print_step", 100)),
        "min_pass_score": int(spec.get("pass", {}).get("min", 0)),
        "min_pattern_matches": TSP_NUM_LOGICAL,
        "snapshot_pages": snapshot_pages,
        "max_neighbors": physical["max_degree"],
        "total_weight": 0,
        "target_energy": 0,
    }
    aux = {
        "dist_scaled": scaled_distance_matrix(dist),
        "opt_length_scaled": opt_length_scaled,
        "opt_tour": opt_tour,
        "global_scale": physical["global_scale"],
        "logical_scale": physical["logical_scale"],
    }
    return problem, aux


def main():
    parser = argparse.ArgumentParser(description="Generate TSP5 full-King's-graph TB includes.")
    parser.add_argument(
        "--spec",
        default="tb/problem_gen/specs/tsp5_full_kings40.json",
        help="JSON spec path, relative to rtl/ by default",
    )
    parser.add_argument("--out-dir", default="tb/generated", help="Output directory relative to rtl/")
    parser.add_argument("--filelist", default="filelist_run_problem.f", help="Output filelist path relative to rtl/")
    args = parser.parse_args()

    spec_path = Path(args.spec).resolve()
    spec = gp.load_json(spec_path)
    problem, aux = build_problem(spec_path, spec)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    gp.write_data_svh(out_dir / "problem_data.svh", problem)
    (out_dir / "problem_score.svh").write_text(
        tsp_score_template(aux["dist_scaled"], aux["opt_length_scaled"], aux["opt_tour"]),
        encoding="ascii",
    )
    gp.write_filelist(Path(args.filelist))

    print("generated {}".format(out_dir / "problem_data.svh"))
    print("generated {}".format(out_dir / "problem_score.svh"))
    print("generated {}".format(args.filelist))
    print(
        "problem={name} kind=tsp5_full_kings40 logical={logical} physical={physical} tile_seeds={tile_seeds} "
        "config_edges={config_edges} clear_edges={clear_edges} sweeps={sweeps} runs={runs}".format(
            name=problem["name"],
            logical=problem["num_logical"],
            physical=len(problem["physical_nodes"]),
            tile_seeds=problem["seed_rows"] * problem["seed_cols"],
            config_edges=len(problem["config_edges"]),
            clear_edges=len(problem["clear_edges"]),
            sweeps=problem["num_sweeps"],
            runs=problem["num_runs"],
        )
    )
    print(
        "max_neighbors={max_neighbors} snapshot_pages={snapshot_pages} i0_levels={i0_levels} opt_length_scaled={opt} global_scale={scale:.8g}".format(
            max_neighbors=problem["max_neighbors"],
            snapshot_pages=problem["snapshot_pages"],
            i0_levels=problem["i0_levels"],
            opt=aux["opt_length_scaled"],
            scale=aux["global_scale"],
        )
    )


if __name__ == "__main__":
    main()
