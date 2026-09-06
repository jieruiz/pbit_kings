#!/usr/bin/env python3
import argparse
import json
import random
import re
from pathlib import Path


NUM_VARIABLES = 10
NUM_CLAUSES = 40
NUM_LOGICAL = NUM_VARIABLES + NUM_CLAUSES
EDGE_RANDOM_MAX_CODE = 127
RTL_I0_LEVEL_MAX = 63


class LFSR32:
    def __init__(self, seed):
        seed = int(seed) & 0xFFFFFFFF
        if seed == 0:
            raise ValueError("LFSR32 seed must be non-zero")
        self.state = seed

    def next_uint32(self):
        bit = (((self.state >> 31) ^ (self.state >> 21) ^ (self.state >> 1) ^ self.state) & 1)
        self.state = ((self.state << 1) & 0xFFFFFFFF) | bit
        return self.state

    def randrange(self, stop):
        if stop <= 0:
            raise ValueError("stop must be positive")
        limit = (2**32 // stop) * stop
        while True:
            x = self.next_uint32()
            if x < limit:
                return x % stop

    def choice(self, seq):
        return seq[self.randrange(len(seq))]


def load_matrix(path, size):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                rows.append([float(x) for x in line.split()])

    if len(rows) != size or any(len(row) != size for row in rows):
        raise ValueError(f"matrix must be {size}x{size}")

    for i in range(size):
        rows[i][i] = 0.0
        for j in range(size):
            if abs(rows[i][j] - rows[j][i]) > 1e-9:
                raise ValueError("matrix must be symmetric")

    return rows


def load_bias(path, size):
    vals = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            vals.extend(float(x) for x in line.split())

    if len(vals) != size:
        raise ValueError(f"bias must have {size} values")
    return vals


def load_clauses(path):
    clauses = []
    lit_re = re.compile(r"^(~)?x(\d+)$")
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            text = line.strip()
            if not text:
                continue
            clause = []
            for raw_lit in text.split(" OR "):
                match = lit_re.match(raw_lit.strip())
                if not match:
                    raise ValueError(f"bad literal {raw_lit!r} in {path}")
                var = int(match.group(2))
                is_positive = match.group(1) is None
                if var < 0 or var >= NUM_VARIABLES:
                    raise ValueError(f"literal variable x{var} out of range")
                clause.append((var, is_positive))
            if len(clause) != 3:
                raise ValueError(f"expected 3 literals per clause: {text}")
            clauses.append(clause)

    if len(clauses) != NUM_CLAUSES:
        raise ValueError(f"expected {NUM_CLAUSES} clauses, got {len(clauses)}")
    return clauses


def load_mapping(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    mapping = {int(k): [int(q) for q in v] for k, v in raw.items()}
    missing = set(range(NUM_LOGICAL)) - set(mapping)
    if missing:
        raise ValueError(f"mapping file missing logical nodes: {sorted(missing)}")
    return {i: mapping[i] for i in range(NUM_LOGICAL)}


def kings_coord(q, kings_cols):
    return q // kings_cols, q % kings_cols


def are_kings_neighbors(q1, q2, kings_cols):
    r1, c1 = kings_coord(q1, kings_cols)
    r2, c2 = kings_coord(q2, kings_cols)
    dr = abs(r1 - r2)
    dc = abs(c1 - c2)
    return dr <= 1 and dc <= 1 and (dr != 0 or dc != 0)


def quantize_to_int(p, bits=7):
    levels = (1 << bits) - 1
    p = max(0.0, min(1.0, float(p)))
    return int(round(p * levels))


def rtl_prob_code_from_python_code(py_code):
    if py_code <= 0:
        return 0
    if py_code >= EDGE_RANDOM_MAX_CODE:
        return EDGE_RANDOM_MAX_CODE
    return py_code - 1


def normalize_signed_coupling(W):
    max_abs = max(abs(W[i][j]) for i in range(NUM_LOGICAL) for j in range(NUM_LOGICAL))
    if max_abs <= 0:
        raise ValueError("all couplings are zero")

    prob = [[0.0 for _ in range(NUM_LOGICAL)] for _ in range(NUM_LOGICAL)]
    sign = [[0 for _ in range(NUM_LOGICAL)] for _ in range(NUM_LOGICAL)]
    for i in range(NUM_LOGICAL):
        for j in range(NUM_LOGICAL):
            prob[i][j] = abs(W[i][j]) / max_abs
            sign[i][j] = 1 if W[i][j] > 0 else (-1 if W[i][j] < 0 else 0)
    return prob, sign


def edge_target_from_coords(r1, c1, r2, c2):
    if r1 == r2 and abs(c1 - c2) == 1:
        return "EDGE_TYPE_EDGE_H", r1, min(c1, c2)
    if c1 == c2 and abs(r1 - r2) == 1:
        return "EDGE_TYPE_EDGE_V", min(r1, r2), c1
    if abs(r1 - r2) == 1 and abs(c1 - c2) == 1:
        top_r = min(r1, r2)
        if (r1 < r2 and c1 < c2) or (r2 < r1 and c2 < c1):
            return "EDGE_TYPE_EDGE_DSE", top_r, min(c1, c2)
        return "EDGE_TYPE_EDGE_DSW", top_r, max(c1, c2)
    raise ValueError(f"not a king-neighbor edge: ({r1},{c1})-({r2},{c2})")


def make_physical_bias_vector(logical_bias, physical_nodes, mapping):
    phys_to_logical = {}
    for logical, chain in mapping.items():
        for q in chain:
            phys_to_logical[q] = logical
    return [logical_bias[phys_to_logical[q]] for q in physical_nodes]


def build_physical_problem(W, logical_bias, mapping, kings_cols):
    P_logical, J_sign_logical = normalize_signed_coupling(W)
    P_logical_q = [[quantize_to_int(P_logical[i][j], 7) / EDGE_RANDOM_MAX_CODE
                    for j in range(NUM_LOGICAL)] for i in range(NUM_LOGICAL)]

    physical_nodes = sorted({q for chain in mapping.values() for q in chain})
    phys_to_idx = {q: idx for idx, q in enumerate(physical_nodes)}
    n_phys = len(physical_nodes)
    P_phys = [[0.0 for _ in range(n_phys)] for _ in range(n_phys)]
    J_sign_phys = [[0 for _ in range(n_phys)] for _ in range(n_phys)]

    for a in range(NUM_LOGICAL):
        for b in range(a + 1, NUM_LOGICAL):
            p_edge = P_logical_q[a][b]
            j_sign = J_sign_logical[a][b]
            if p_edge <= 0:
                continue

            couplers = []
            for qa in mapping[a]:
                for qb in mapping[b]:
                    if are_kings_neighbors(qa, qb, kings_cols):
                        couplers.append((qa, qb))
            if not couplers:
                continue

            p_each = p_edge / len(couplers)
            for qa, qb in couplers:
                ia = phys_to_idx[qa]
                ib = phys_to_idx[qb]
                P_phys[ia][ib] = max(P_phys[ia][ib], p_each)
                P_phys[ib][ia] = P_phys[ia][ib]
                J_sign_phys[ia][ib] = j_sign
                J_sign_phys[ib][ia] = j_sign

    for chain in mapping.values():
        for a_pos in range(len(chain)):
            for b_pos in range(a_pos + 1, len(chain)):
                qa = chain[a_pos]
                qb = chain[b_pos]
                if are_kings_neighbors(qa, qb, kings_cols):
                    ia = phys_to_idx[qa]
                    ib = phys_to_idx[qb]
                    P_phys[ia][ib] = 1.0
                    P_phys[ib][ia] = 1.0
                    J_sign_phys[ia][ib] = -1
                    J_sign_phys[ib][ia] = -1

    bias_raw = make_physical_bias_vector(logical_bias, physical_nodes, mapping)
    max_edge_abs = max((P_phys[i][j] for i in range(n_phys) for j in range(n_phys)), default=0.0)
    max_bias_abs = max((abs(x) for x in bias_raw), default=0.0)
    global_scale = max(max_edge_abs, max_bias_abs, 1e-12)

    P_phys_int = [[quantize_to_int(P_phys[i][j] / global_scale, 7)
                   for j in range(n_phys)] for i in range(n_phys)]
    bias_prob_int = [quantize_to_int(abs(x) / global_scale, 7) for x in bias_raw]
    bias_sign = [1 if x > 0 else (-1 if x < 0 else 0) for x in bias_raw]
    return physical_nodes, phys_to_idx, P_phys_int, J_sign_phys, bias_prob_int, bias_sign


def make_seed(seed_rng):
    seed = seed_rng.randrange(1, 2**32)
    return seed if seed else 1


def make_pbit_seeds(n, master_seed):
    seed_rng = random.Random(master_seed)
    seeds = set()
    while len(seeds) < n:
        seeds.add(make_seed(seed_rng))
    return sorted(seeds)


def build_node_seeds_and_init(physical_nodes, kings_cols, kings_rows, seed_master, run_seed):
    tile_rows = (kings_rows + 1) // 2
    tile_cols = (kings_cols + 1) // 2
    tile_seeds = make_pbit_seeds(tile_rows * tile_cols, seed_master)

    global_seed = make_seed(random.Random(run_seed))
    global_rng = LFSR32(global_seed)

    seeds = []
    init_spins = []
    for q in physical_nodes:
        row, col = kings_coord(q, kings_cols)
        tile_id = (row // 2) * tile_cols + (col // 2)
        seed = (tile_seeds[tile_id] ^ ((q + 1) * 0x9E3779B9)) & 0xFFFFFFFF
        seeds.append(seed if seed else 1)
        init_spins.append(1 if global_rng.choice([-1, 1]) > 0 else 0)

    return seeds, init_spins, tile_rows, tile_cols, len(tile_seeds), global_seed


def build_multi_run_node_data(physical_nodes, kings_cols, kings_rows, seed_master_start,
                              seed_master_step, run_seed_start, num_runs):
    all_seeds = []
    all_init_spins = []
    global_seeds = []
    tile_info = None

    for run_idx in range(num_runs):
        seed_master = seed_master_start + run_idx * seed_master_step
        run_seed = run_seed_start + run_idx
        seeds, init_spins, tile_rows, tile_cols, num_tile_lfsrs, global_seed = build_node_seeds_and_init(
            physical_nodes, kings_cols, kings_rows, seed_master, run_seed
        )
        all_seeds.append(seeds)
        all_init_spins.append(init_spins)
        global_seeds.append(global_seed)
        tile_info = (tile_rows, tile_cols, num_tile_lfsrs)

    return all_seeds, all_init_spins, global_seeds, tile_info


def build_clear_edges(kings_rows, clear_cols):
    edges = []
    for r in range(kings_rows):
        for c in range(clear_cols - 1):
            edges.append(("EDGE_TYPE_EDGE_H", r, c))
    for r in range(kings_rows - 1):
        for c in range(clear_cols):
            edges.append(("EDGE_TYPE_EDGE_V", r, c))
    for r in range(kings_rows - 1):
        for c in range(clear_cols - 1):
            edges.append(("EDGE_TYPE_EDGE_DSE", r, c))
    for r in range(kings_rows - 1):
        for c in range(1, clear_cols):
            edges.append(("EDGE_TYPE_EDGE_DSW", r, c))
    return edges


def build_config_edges(physical_nodes, prob, sign, kings_cols):
    edges = []
    for ia in range(len(physical_nodes)):
        for ib in range(ia + 1, len(physical_nodes)):
            if prob[ia][ib] <= 0:
                continue
            r1, c1 = kings_coord(physical_nodes[ia], kings_cols)
            r2, c2 = kings_coord(physical_nodes[ib], kings_cols)
            edge_type, row, col = edge_target_from_coords(r1, c1, r2, c2)
            rtl_prob = rtl_prob_code_from_python_code(prob[ia][ib])
            # Python uses h = -sum(J*s) + bias, while RTL edge_sign=1 contributes +s.
            rtl_sign = 0 if sign[ia][ib] > 0 else 1
            edges.append((edge_type, row, col, rtl_prob, rtl_sign))
    return edges


def python_like_schedule(num_sweeps, num_i0_levels):
    counts = [0 for _ in range(num_i0_levels)]
    for sweep in range(num_sweeps):
        level = round((num_i0_levels - 1) * sweep / max(1, num_sweeps - 1))
        counts[level] += 1
    return counts


def build_i0_levels(i0_start, i0_end, num_i0_levels):
    levels = []
    for idx in range(num_i0_levels):
        alpha = idx / max(1, num_i0_levels - 1)
        i0 = i0_start + (i0_end - i0_start) * alpha
        level = int(round(i0 * RTL_I0_LEVEL_MAX / i0_end))
        levels.append(max(0, min(RTL_I0_LEVEL_MAX, level)))
    return levels


def fixed_i0_level(fixed_i0, i0_end):
    if fixed_i0 < 0:
        raise ValueError("--fixed-i0 must be non-negative")
    if i0_end <= 0:
        raise ValueError("--i0-end must be positive")
    level = int(round(fixed_i0 * RTL_I0_LEVEL_MAX / i0_end))
    return max(0, min(RTL_I0_LEVEL_MAX, level))


def sv_arr_assign(name, values, fmt):
    return [f"        {name}[{idx}] = {fmt(value)};" for idx, value in enumerate(values)]


def write_svh(path, args, physical_nodes, phys_to_idx, config_edges, clear_edges,
              node_seeds_by_run, init_spins_by_run, bias_prob, bias_sign, clauses, mapping,
              tile_info, global_seeds, i0_levels):
    chain_entries = []
    chain_start = [0]
    for logical in range(NUM_LOGICAL):
        chain_entries.extend(phys_to_idx[q] for q in mapping[logical])
        chain_start.append(len(chain_entries))

    rows = []
    cols = []
    for q in physical_nodes:
        r, c = kings_coord(q, args.kings_cols)
        rows.append(r)
        cols.append(c)

    clause_vars = []
    clause_pos = []
    for clause in clauses:
        for var, is_positive in clause:
            clause_vars.append(var)
            clause_pos.append(1 if is_positive else 0)

    rtl_bias_prob = [rtl_prob_code_from_python_code(code) for code in bias_prob]
    rtl_bias_sign = [1 if sign > 0 else 0 for sign in bias_sign]
    intervals = python_like_schedule(args.num_sweeps, len(i0_levels))
    num_sweeps = sum(intervals)

    lines = []
    lines.append("`ifndef TB_KSAT_10V40C_DATA_SVH")
    lines.append("`define TB_KSAT_10V40C_DATA_SVH")
    lines.append("// Generated by tb/gen_ksat_10v40c_data.py. Re-run when J, bias, clauses, or mapping changes.")
    lines.append(f"localparam int unsigned K10_NUM_VARIABLES = {NUM_VARIABLES};")
    lines.append(f"localparam int unsigned K10_NUM_CLAUSES = {NUM_CLAUSES};")
    lines.append(f"localparam int unsigned K10_LITS_PER_CLAUSE = 3;")
    lines.append(f"localparam int unsigned K10_NUM_LOGICAL = {NUM_LOGICAL};")
    lines.append(f"localparam int unsigned K10_NUM_PHYSICAL = {len(physical_nodes)};")
    lines.append(f"localparam int unsigned K10_NUM_CONFIG_EDGES = {len(config_edges)};")
    lines.append(f"localparam int unsigned K10_NUM_CLEAR_EDGES = {len(clear_edges)};")
    lines.append(f"localparam int unsigned K10_NUM_CHAIN_ENTRIES = {len(chain_entries)};")
    lines.append(f"localparam int unsigned K10_NUM_SEED_RUNS = {args.num_runs};")
    lines.append(f"localparam int unsigned K10_NUM_I0_LEVELS = {len(i0_levels)};")
    lines.append(f"localparam int unsigned K10_NUM_SWEEPS = {num_sweeps};")
    lines.append(f"localparam int unsigned K10_NUM_MAJORITY = {args.num_majority};")
    lines.append(f"localparam int unsigned K10_MIN_PASS_SAT = {args.min_satisfied};")
    lines.append(f"localparam int unsigned K10_FIXED_I0_LEVEL = {i0_levels[0]};")
    lines.append(f"localparam int unsigned K10_KINGS_ROWS = {args.kings_rows};")
    lines.append(f"localparam int unsigned K10_KINGS_COLS = {args.kings_cols};")
    lines.append(f"localparam int unsigned K10_TILE_ROWS = {tile_info[0]};")
    lines.append(f"localparam int unsigned K10_TILE_COLS = {tile_info[1]};")
    lines.append(f"localparam int unsigned K10_NUM_TILE_LFSRS = {tile_info[2]};")
    lines.append(f"localparam int unsigned K10_SEED_MASTER_START = {args.seed_master_start};")
    lines.append(f"localparam int unsigned K10_SEED_MASTER_STEP = {args.seed_master_step};")
    lines.append(f"localparam int unsigned K10_RUN_SEED_START = {args.run_seed};")
    lines.append("")
    lines.append("logic [NODE_TARGET_ROW_WIDTH-1:0] k10_phys_row [K10_NUM_PHYSICAL];")
    lines.append("logic [NODE_TARGET_COL_WIDTH-1:0] k10_phys_col [K10_NUM_PHYSICAL];")
    lines.append("logic [31:0] k10_global_seed [K10_NUM_SEED_RUNS];")
    lines.append("logic [31:0] k10_node_seed [K10_NUM_SEED_RUNS][K10_NUM_PHYSICAL];")
    lines.append("logic k10_node_init_spin [K10_NUM_SEED_RUNS][K10_NUM_PHYSICAL];")
    lines.append("logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] k10_node_bias_prob [K10_NUM_PHYSICAL];")
    lines.append("logic k10_node_bias_sign [K10_NUM_PHYSICAL];")
    lines.append("logic [EDGE_TYPE_WIDTH-1:0] k10_edge_type [K10_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TARGET_ROW_WIDTH-1:0] k10_edge_row [K10_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TARGET_COL_WIDTH-1:0] k10_edge_col [K10_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] k10_edge_prob [K10_NUM_CONFIG_EDGES];")
    lines.append("logic k10_edge_sign [K10_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TYPE_WIDTH-1:0] k10_clear_edge_type [K10_NUM_CLEAR_EDGES];")
    lines.append("logic [EDGE_TARGET_ROW_WIDTH-1:0] k10_clear_edge_row [K10_NUM_CLEAR_EDGES];")
    lines.append("logic [EDGE_TARGET_COL_WIDTH-1:0] k10_clear_edge_col [K10_NUM_CLEAR_EDGES];")
    lines.append("int unsigned k10_chain_start [K10_NUM_LOGICAL + 1];")
    lines.append("int unsigned k10_chain_phys_idx [K10_NUM_CHAIN_ENTRIES];")
    lines.append("int unsigned k10_clause_var [K10_NUM_CLAUSES * K10_LITS_PER_CLAUSE];")
    lines.append("logic k10_clause_pos [K10_NUM_CLAUSES * K10_LITS_PER_CLAUSE];")
    lines.append("logic [I0_LEVEL_WIDTH-1:0] k10_i0_level [K10_NUM_I0_LEVELS];")
    lines.append("logic [SWEEP_INTERVAL_WIDTH-1:0] k10_sweep_interval [K10_NUM_I0_LEVELS];")
    lines.append("")
    lines.append("task automatic load_ksat_10v40c_data();")
    lines.append("    begin")
    lines.extend(sv_arr_assign("k10_phys_row", rows, lambda v: f"6'd{v}"))
    lines.extend(sv_arr_assign("k10_phys_col", cols, lambda v: f"6'd{v}"))
    lines.extend(sv_arr_assign("k10_global_seed", global_seeds, lambda v: f"32'h{v:08x}"))
    for run_idx, node_seeds in enumerate(node_seeds_by_run):
        for node_idx, seed in enumerate(node_seeds):
            lines.append(f"        k10_node_seed[{run_idx}][{node_idx}] = 32'h{seed:08x};")
    for run_idx, init_spins in enumerate(init_spins_by_run):
        for node_idx, init_spin in enumerate(init_spins):
            lines.append(f"        k10_node_init_spin[{run_idx}][{node_idx}] = 1'b{init_spin};")
    lines.extend(sv_arr_assign("k10_node_bias_prob", rtl_bias_prob, lambda v: f"7'd{v}"))
    lines.extend(sv_arr_assign("k10_node_bias_sign", rtl_bias_sign, lambda v: f"1'b{v}"))
    for idx, (edge_type, row, col, prob_code, rtl_sign) in enumerate(config_edges):
        lines.append(f"        k10_edge_type[{idx}] = {edge_type};")
        lines.append(f"        k10_edge_row[{idx}] = 6'd{row};")
        lines.append(f"        k10_edge_col[{idx}] = 6'd{col};")
        lines.append(f"        k10_edge_prob[{idx}] = 7'd{prob_code};")
        lines.append(f"        k10_edge_sign[{idx}] = 1'b{rtl_sign};")
    for idx, (edge_type, row, col) in enumerate(clear_edges):
        lines.append(f"        k10_clear_edge_type[{idx}] = {edge_type};")
        lines.append(f"        k10_clear_edge_row[{idx}] = 6'd{row};")
        lines.append(f"        k10_clear_edge_col[{idx}] = 6'd{col};")
    lines.extend(sv_arr_assign("k10_chain_start", chain_start, lambda v: f"{v}"))
    lines.extend(sv_arr_assign("k10_chain_phys_idx", chain_entries, lambda v: f"{v}"))
    lines.extend(sv_arr_assign("k10_clause_var", clause_vars, lambda v: f"{v}"))
    lines.extend(sv_arr_assign("k10_clause_pos", clause_pos, lambda v: f"1'b{v}"))
    lines.extend(sv_arr_assign("k10_i0_level", i0_levels, lambda v: f"6'd{v}"))
    lines.extend(sv_arr_assign("k10_sweep_interval", intervals, lambda v: f"16'd{v}"))
    lines.append("    end")
    lines.append("endtask")
    lines.append("`endif")
    lines.append("")
    path.write_text("\n".join(lines), encoding="ascii")


def main():
    parser = argparse.ArgumentParser(description="Generate SV data for the 10-variable 40-clause 3-SAT UART testbench.")
    parser.add_argument("--j-path", default="../../../p-bit_withbias/three_sat_10v40c_tile_lfsr_multirun_7_bit_quant/three_sat_10v40c_J50.txt")
    parser.add_argument("--bias-path", default="../../../p-bit_withbias/three_sat_10v40c_tile_lfsr_multirun_7_bit_quant/three_sat_10v40c_bias50.txt")
    parser.add_argument("--clauses-path", default="../../../p-bit_withbias/three_sat_10v40c_tile_lfsr_multirun_7_bit_quant/three_sat_10v40c_clauses.txt")
    parser.add_argument("--mapping-path", default="../../../KingsGraph_Embedding_W50_Best_19x19.json")
    parser.add_argument("--out", default="tb/tb_ksat_10v40c_data.svh")
    parser.add_argument("--kings-cols", type=int, default=19)
    parser.add_argument("--kings-rows", type=int, default=20)
    parser.add_argument("--num-runs", type=int, default=10)
    parser.add_argument("--seed-master-start", type=int, default=2501)
    parser.add_argument("--seed-master-step", type=int, default=10)
    parser.add_argument("--run-seed", type=int, default=314592)
    parser.add_argument("--num-majority", type=int, default=5)
    parser.add_argument("--num-sweeps", type=int, default=500)
    parser.add_argument("--num-i0-levels", type=int, default=16)
    parser.add_argument("--i0-start", type=float, default=0.5)
    parser.add_argument("--i0-end", type=float, default=6.0)
    parser.add_argument("--fixed-i0", type=float, default=1.0)
    parser.add_argument("--min-satisfied", type=int, default=40)
    args = parser.parse_args()

    if args.num_runs < 1:
        raise ValueError("--num-runs must be >= 1")
    if args.num_i0_levels < 1 or args.num_i0_levels > 64:
        raise ValueError("--num-i0-levels must be in [1, 64]")
    if args.num_i0_levels % 4 != 0:
        raise ValueError("--num-i0-levels must be a multiple of 4 for the current TB packer")
    if args.num_sweeps < args.num_i0_levels:
        raise ValueError("--num-sweeps must be >= --num-i0-levels")

    W = load_matrix(args.j_path, NUM_LOGICAL)
    bias = load_bias(args.bias_path, NUM_LOGICAL)
    clauses = load_clauses(args.clauses_path)
    mapping = load_mapping(args.mapping_path)
    physical_nodes, phys_to_idx, prob, sign, bias_prob, bias_sign = build_physical_problem(
        W, bias, mapping, args.kings_cols
    )
    config_edges = build_config_edges(physical_nodes, prob, sign, args.kings_cols)
    clear_edges = build_clear_edges(args.kings_rows, args.kings_cols + 1)
    node_seeds_by_run, init_spins_by_run, global_seeds, tile_info = build_multi_run_node_data(
        physical_nodes,
        args.kings_cols,
        args.kings_rows,
        args.seed_master_start,
        args.seed_master_step,
        args.run_seed,
        args.num_runs,
    )
    i0_level = fixed_i0_level(args.fixed_i0, args.i0_end)
    i0_levels = [i0_level for _ in range(args.num_i0_levels)]

    max_neighbors = 0
    for i in range(len(physical_nodes)):
        max_neighbors = max(max_neighbors, sum(1 for p in prob[i] if p > 0))
    if max_neighbors > 8:
        raise ValueError(f"Generated physical problem has max_neighbors={max_neighbors}, exceeds RTL limit 8")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    write_svh(
        out,
        args,
        physical_nodes,
        phys_to_idx,
        config_edges,
        clear_edges,
        node_seeds_by_run,
        init_spins_by_run,
        bias_prob,
        bias_sign,
        clauses,
        mapping,
        tile_info,
        global_seeds,
        i0_levels,
    )
    print(f"generated {out}")
    print(f"physical_nodes={len(physical_nodes)} config_edges={len(config_edges)} clear_edges={len(clear_edges)}")
    print(f"clauses={len(clauses)} max_neighbors={max_neighbors} nonzero_bias={sum(1 for x in bias_prob if x > 0)}")
    print(f"num_runs={args.num_runs} seed_master_start={args.seed_master_start} seed_master_step={args.seed_master_step}")
    print(f"num_sweeps={args.num_sweeps} num_majority={args.num_majority} fixed_i0={args.fixed_i0} fixed_i0_level={i0_level}")
    print(f"min_satisfied={args.min_satisfied}")


if __name__ == "__main__":
    main()
