#!/usr/bin/env python3
"""Generate a native 40x40 King's-graph MaxCut Verilog simulation case.

This generator mirrors p_bit_native_king_maxcut_40x40_tile_lfsr_7_bit.py:
each hardware p-bit is one logical MaxCut variable, and all native H/V/DSE/DSW
King's-graph edges are configured directly on the RTL array.
"""

import argparse
import json
import random
import sys
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import gen_problem as gp  # noqa: E402


EDGE_RANDOM_MAX_CODE = 127


def build_native_king_edges(rows, cols):
    edges = []
    for r in range(rows):
        for c in range(cols):
            a = r * cols + c
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr == 0 and dc == 0:
                        continue
                    rr = r + dr
                    cc = c + dc
                    if 0 <= rr < rows and 0 <= cc < cols:
                        b = rr * cols + cc
                        if a < b:
                            edge_type, edge_row, edge_col = gp.edge_target_from_coords(r, c, rr, cc)
                            edges.append((a, b, edge_type, edge_row, edge_col))
    return edges


def build_weight_codes(edges, problem_cfg):
    mode = problem_cfg.get("weight_mode", "random_int")
    weight_seed = int(problem_cfg.get("weight_seed", 20260813))
    uniform_weight_code = int(problem_cfg.get("uniform_weight_code", EDGE_RANDOM_MAX_CODE))
    random_levels = tuple(int(x) for x in problem_cfg.get("random_levels", [32, 64, 127]))
    rng = random.Random(weight_seed)

    weights = []
    for _ in edges:
        if mode == "uniform":
            code = uniform_weight_code
        elif mode == "random_int":
            code = rng.randint(1, EDGE_RANDOM_MAX_CODE)
        elif mode == "random_levels":
            code = rng.choice(random_levels)
        else:
            raise ValueError("weight_mode must be one of: uniform, random_int, random_levels")
        if code < 1 or code > EDGE_RANDOM_MAX_CODE:
            raise ValueError("edge weight code must be in [1, 127], got {}".format(code))
        weights.append(int(code))
    return weights


def build_native_king_problem(spec_path, spec):
    hw = spec.get("hardware", {})
    run = spec.get("run", {})
    problem_cfg = spec.get("problem", {})
    rows = int(hw.get("kings_rows", 40))
    cols = int(hw.get("kings_cols", 40))
    rtl_cols = int(hw.get("rtl_cols", 40))
    if rows != 40 or cols != 40 or rtl_cols != 40:
        raise ValueError("native_king_maxcut is intended for the full 40x40 RTL array")

    num_logical = rows * cols
    physical_nodes = list(range(num_logical))
    phys_to_idx = {q: q for q in physical_nodes}
    mapping = {q: [q] for q in physical_nodes}

    native_edges = build_native_king_edges(rows, cols)
    weights = build_weight_codes(native_edges, problem_cfg)

    config_edges = []
    logical_edges = []
    logical_edge_signs = []
    for idx, (a, b, edge_type, edge_row, edge_col) in enumerate(native_edges):
        weight = weights[idx]
        # Python code uses code 127 as always active. RTL prob code 127 also means always active.
        # MaxCut rewards opposite spins, so each positive cut weight must be
        # configured as an antiferromagnetic RTL coupler: edge_sign=0 means J=-1.
        config_edges.append((edge_type, edge_row, edge_col, weight, 0))
        logical_edges.append((a, b, weight))
        logical_edge_signs.append(1)

    num_runs = int(run.get("num_runs", 1))
    node_seeds, init_spins, global_seeds = gp.build_maxcut_node_data(
        physical_nodes,
        num_runs,
        int(run.get("seed_master_start", run.get("seed_master", 24680))),
        int(run.get("seed_master_step", 1)),
        int(run.get("run_seed", 0)),
        cols,
    )
    i0_levels = gp.build_i0_levels(run, spec_path)
    num_sweeps, intervals = gp.build_intervals(run, len(i0_levels))
    clear_edges = gp.build_clear_edges(rows, cols)
    chain_start, chain_phys_idx = gp.chain_arrays(mapping, phys_to_idx)
    snapshot_width = int(spec.get("snapshot_width", gp.RTL_SNAPSHOT_WIDTH))
    snapshot_pages = int((num_logical + snapshot_width - 1) // snapshot_width)

    return {
        "name": spec["name"],
        "kind": "maxcut",
        "num_logical": num_logical,
        "num_variables": 0,
        "num_clauses": 0,
        "lits_per_clause": 0,
        "kings_rows": rows,
        "kings_cols": cols,
        "physical_nodes": physical_nodes,
        "phys_to_idx": phys_to_idx,
        "config_edges": config_edges,
        "clear_edges": clear_edges,
        "node_seeds": node_seeds,
        "init_spins": init_spins,
        "global_seeds": global_seeds,
        "bias_prob": [0 for _ in physical_nodes],
        "bias_sign": [1 for _ in physical_nodes],
        "chain_start": chain_start,
        "chain_phys_idx": chain_phys_idx,
        "logical_edges": logical_edges,
        "logical_edge_signs": logical_edge_signs,
        "target_spins": [1 for _ in physical_nodes],
        "clauses": [],
        "i0_levels": i0_levels,
        "intervals": intervals,
        "num_sweeps": num_sweeps,
        "num_majority": int(run.get("num_majority", 7)),
        "num_runs": num_runs,
        "progress_print_step": int(run.get("progress_print_step", 100)),
        "min_pass_score": int(spec.get("pass", {}).get("min", 0)),
        "min_pattern_matches": num_logical,
        "snapshot_pages": snapshot_pages,
        "max_neighbors": 8,
        "total_weight": sum(weights),
        "target_energy": 0,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate native 40x40 King's-graph MaxCut TB includes.")
    parser.add_argument(
        "--spec",
        default="tb/problem_gen/specs/native_king_maxcut_40x40.json",
        help="JSON spec path, relative to rtl/ by default",
    )
    parser.add_argument("--out-dir", default="tb/generated", help="Output directory relative to rtl/")
    parser.add_argument("--filelist", default="filelist_run_problem.f", help="Output filelist path relative to rtl/")
    args = parser.parse_args()

    spec_path = Path(args.spec).resolve()
    spec = gp.load_json(spec_path)
    problem = build_native_king_problem(spec_path, spec)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    gp.write_data_svh(out_dir / "problem_data.svh", problem)
    gp.write_score_svh(out_dir / "problem_score.svh", problem)
    gp.write_filelist(Path(args.filelist))

    print("generated {}".format(out_dir / "problem_data.svh"))
    print("generated {}".format(out_dir / "problem_score.svh"))
    print("generated {}".format(args.filelist))
    print(
        "problem={name} kind=native_king_maxcut logical={logical} physical={physical} "
        "config_edges={config_edges} clear_edges={clear_edges} sweeps={sweeps} runs={runs}".format(
            name=problem["name"],
            logical=problem["num_logical"],
            physical=len(problem["physical_nodes"]),
            config_edges=len(problem["config_edges"]),
            clear_edges=len(problem["clear_edges"]),
            sweeps=problem["num_sweeps"],
            runs=problem["num_runs"],
        )
    )
    print(
        "total_weight={total_weight} max_neighbors={max_neighbors} snapshot_pages={snapshot_pages} i0_levels={i0}".format(
            total_weight=problem["total_weight"],
            max_neighbors=problem["max_neighbors"],
            snapshot_pages=problem["snapshot_pages"],
            i0=problem["i0_levels"],
        )
    )


if __name__ == "__main__":
    main()
