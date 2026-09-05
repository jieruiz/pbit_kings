#!/usr/bin/env python3
"""Generate generic p-bit UART testbench data and score includes.

The generator converts a problem spec JSON file into:
  - tb/generated/problem_data.svh: hardware configuration arrays
  - tb/generated/problem_score.svh: problem-specific scoring code

It intentionally uses only the Python standard library so it can run on the
remote simulation host without package installation.
"""

import argparse
import csv
import json
import math
import random
from pathlib import Path


EDGE_RANDOM_MAX_CODE = 127
RTL_SNAPSHOT_WIDTH = 320  # Must match pbit_pkg.sv SNAPSHOT_WIDTH.

EDGE_TYPE_H = "EDGE_TYPE_EDGE_H"
EDGE_TYPE_V = "EDGE_TYPE_EDGE_V"
EDGE_TYPE_DSE = "EDGE_TYPE_EDGE_DSE"
EDGE_TYPE_DSW = "EDGE_TYPE_EDGE_DSW"


def resolve_path(spec_path: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return (spec_path.parent / path).resolve()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_i0_table(path: Path):
    rows = []
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rows.append((int(row["level"]), float(row["I0"])))
    if not rows:
        raise ValueError(f"{path} does not contain any I0 rows")
    return rows


def load_matrix(path: Path, size=None):
    rows = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        rows.append([float(x) for x in raw.split()])
    if size is not None and (len(rows) != size or any(len(row) != size for row in rows)):
        raise ValueError(f"{path} must be {size}x{size}")
    if size is None:
        size = len(rows)
        if size == 0 or any(len(row) != size for row in rows):
            raise ValueError(f"{path} must be a non-empty square matrix")
    return rows


def load_bias(path: Path, size: int):
    values = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if raw:
            values.extend(float(x) for x in raw.split())
    if len(values) != size:
        raise ValueError(f"{path} must contain {size} bias values")
    return values


def load_clauses(path: Path, num_variables: int, lits_per_clause: int):
    clauses = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        tokens = raw.replace(",", " ").replace("(", " ").replace(")", " ").split()
        tokens = [tok for tok in tokens if tok.upper() not in {"OR", "AND"}]
        if len(tokens) != lits_per_clause:
            raise ValueError(f"clause {raw!r} does not have {lits_per_clause} literals")
        clause = []
        for tok in tokens:
            negated = tok.startswith("~") or tok.startswith("-")
            clean = tok[1:] if negated else tok
            if clean.startswith("x") or clean.startswith("X"):
                var = int(clean[1:])
                positive = not negated
            else:
                lit = int(tok)
                if lit == 0:
                    raise ValueError("DIMACS-style zero literal is not supported in this simple parser")
                var = abs(lit) - 1
                positive = lit > 0
            if var < 0 or var >= num_variables:
                raise ValueError(f"literal {tok} is outside variable range")
            clause.append((var, positive))
        clauses.append(clause)
    return clauses


def load_mapping(path: Path, num_logical: int):
    raw = load_json(path)
    mapping = {}
    for key, value in raw.items():
        mapping[int(key)] = [int(x) for x in value]
    missing = set(range(num_logical)) - set(mapping)
    if missing:
        raise ValueError(f"mapping missing logical nodes: {sorted(missing)}")
    return {idx: mapping[idx] for idx in range(num_logical)}


def kings_coord(q: int, kings_cols: int):
    return q // kings_cols, q % kings_cols


def are_kings_neighbors(q1: int, q2: int, kings_cols: int):
    r1, c1 = kings_coord(q1, kings_cols)
    r2, c2 = kings_coord(q2, kings_cols)
    dr = abs(r1 - r2)
    dc = abs(c1 - c2)
    return max(dr, dc) == 1


def edge_target_from_coords(r1: int, c1: int, r2: int, c2: int):
    if r1 == r2 and abs(c1 - c2) == 1:
        return EDGE_TYPE_H, r1, min(c1, c2)
    if c1 == c2 and abs(r1 - r2) == 1:
        return EDGE_TYPE_V, min(r1, r2), c1
    if abs(r1 - r2) == 1 and abs(c1 - c2) == 1:
        top_r = min(r1, r2)
        if (r2 == r1 + 1 and c2 == c1 + 1) or (r1 == r2 + 1 and c1 == c2 + 1):
            return EDGE_TYPE_DSE, top_r, min(c1, c2)
        return EDGE_TYPE_DSW, top_r, max(c1, c2)
    raise ValueError(f"not a king-neighbor edge: ({r1},{c1}) to ({r2},{c2})")


def quantize_to_int(prob: float, bits: int = 7):
    levels = (1 << bits) - 1
    prob = max(0.0, min(1.0, float(prob)))
    return int(round(prob * levels))


def rtl_prob_code_from_python_code(py_code: int):
    if py_code <= 0:
        return 0
    if py_code >= EDGE_RANDOM_MAX_CODE:
        return EDGE_RANDOM_MAX_CODE
    return py_code - 1


def edge_sign_for_rtl(j_sign: int):
    # RTL local field uses edge_sign=1 as +neighbor and 0 as -neighbor.
    # The reference Ising/K-SAT formulation feeds -edge_sum + bias, so signs invert.
    return 0 if j_sign > 0 else 1


def normalize_unsigned_weights(W):
    n = len(W)
    max_w = max(abs(W[i][j]) for i in range(n) for j in range(n))
    if max_w == 0:
        max_w = 1
    prob = [[0 for _ in range(n)] for _ in range(n)]
    sign = [[0 for _ in range(n)] for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i == j or W[i][j] == 0:
                continue
            py_code = quantize_to_int(abs(W[i][j]) / max_w, 7)
            prob[i][j] = rtl_prob_code_from_python_code(py_code)
            sign[i][j] = 0 if W[i][j] > 0 else 1
    return prob, sign


def normalize_signed_coupling(W):
    n = len(W)
    max_abs = max(abs(W[i][j]) for i in range(n) for j in range(n))
    if max_abs == 0:
        max_abs = 1
    prob = [[0 for _ in range(n)] for _ in range(n)]
    sign = [[0 for _ in range(n)] for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i == j or W[i][j] == 0:
                continue
            py_code = quantize_to_int(abs(W[i][j]) / max_abs, 7)
            prob[i][j] = rtl_prob_code_from_python_code(py_code)
            sign[i][j] = edge_sign_for_rtl(W[i][j])
    return prob, sign


def build_physical_edges(logical_prob, logical_sign, mapping, kings_cols):
    physical_nodes = sorted({q for chain in mapping.values() for q in chain})
    phys_to_idx = {q: idx for idx, q in enumerate(physical_nodes)}
    n_phys = len(physical_nodes)
    prob = [[0 for _ in range(n_phys)] for _ in range(n_phys)]
    sign = [[0 for _ in range(n_phys)] for _ in range(n_phys)]

    n_logical = len(mapping)
    for a in range(n_logical):
        for b in range(a + 1, n_logical):
            p_edge = logical_prob[a][b]
            if p_edge == 0:
                continue
            s_edge = logical_sign[a][b]
            for qa in mapping[a]:
                for qb in mapping[b]:
                    if are_kings_neighbors(qa, qb, kings_cols):
                        ia = phys_to_idx[qa]
                        ib = phys_to_idx[qb]
                        prob[ia][ib] = p_edge
                        prob[ib][ia] = p_edge
                        sign[ia][ib] = s_edge
                        sign[ib][ia] = s_edge

    # Strong ferromagnetic chain couplings.
    for chain in mapping.values():
        for idx_a in range(len(chain)):
            for idx_b in range(idx_a + 1, len(chain)):
                qa = chain[idx_a]
                qb = chain[idx_b]
                if are_kings_neighbors(qa, qb, kings_cols):
                    ia = phys_to_idx[qa]
                    ib = phys_to_idx[qb]
                    prob[ia][ib] = EDGE_RANDOM_MAX_CODE
                    prob[ib][ia] = EDGE_RANDOM_MAX_CODE
                    sign[ia][ib] = 1
                    sign[ib][ia] = 1
    return physical_nodes, phys_to_idx, prob, sign


def build_maxcut_physical_edges_split(W, mapping, kings_cols):
    max_w = max(W[i][j] for i in range(len(W)) for j in range(len(W)))
    if max_w <= 0:
        raise ValueError("maxcut weights must contain at least one positive edge")

    physical_nodes = sorted({q for chain in mapping.values() for q in chain})
    phys_to_idx = {q: idx for idx, q in enumerate(physical_nodes)}
    n_phys = len(physical_nodes)
    prob = [[0 for _ in range(n_phys)] for _ in range(n_phys)]
    sign = [[0 for _ in range(n_phys)] for _ in range(n_phys)]

    for a in range(len(W)):
        for b in range(a + 1, len(W)):
            if W[a][b] <= 0:
                continue

            p_edge = quantize_to_int(W[a][b] / max_w, 7) / EDGE_RANDOM_MAX_CODE
            if p_edge <= 0:
                continue

            couplers = []
            for qa in mapping[a]:
                for qb in mapping[b]:
                    if are_kings_neighbors(qa, qb, kings_cols):
                        couplers.append((qa, qb))
            if not couplers:
                continue

            # Match the original W50 flow: split one logical MaxCut edge across
            # all available physical couplers so embedding density does not
            # amplify that logical edge's total strength.
            p_each_code = quantize_to_int(p_edge / len(couplers), 7)
            rtl_prob = rtl_prob_code_from_python_code(p_each_code)
            for qa, qb in couplers:
                ia = phys_to_idx[qa]
                ib = phys_to_idx[qb]
                prob[ia][ib] = max(prob[ia][ib], rtl_prob)
                prob[ib][ia] = prob[ia][ib]
                sign[ia][ib] = 0
                sign[ib][ia] = 0

    # Strong ferromagnetic chain couplings keep each logical variable's chain
    # coherent; these are constraints, not split logical problem edges.
    for chain in mapping.values():
        for idx_a in range(len(chain)):
            for idx_b in range(idx_a + 1, len(chain)):
                qa = chain[idx_a]
                qb = chain[idx_b]
                if are_kings_neighbors(qa, qb, kings_cols):
                    ia = phys_to_idx[qa]
                    ib = phys_to_idx[qb]
                    prob[ia][ib] = EDGE_RANDOM_MAX_CODE
                    prob[ib][ia] = EDGE_RANDOM_MAX_CODE
                    sign[ia][ib] = 1
                    sign[ib][ia] = 1

    return physical_nodes, phys_to_idx, prob, sign


def build_config_edges(physical_nodes, prob, sign, kings_cols):
    edges = []
    for ia in range(len(physical_nodes)):
        for ib in range(ia + 1, len(physical_nodes)):
            if prob[ia][ib] <= 0:
                continue
            r1, c1 = kings_coord(physical_nodes[ia], kings_cols)
            r2, c2 = kings_coord(physical_nodes[ib], kings_cols)
            edge_type, row, col = edge_target_from_coords(r1, c1, r2, c2)
            edges.append((edge_type, row, col, prob[ia][ib], sign[ia][ib]))
    return edges


def build_clear_edges(kings_rows: int, clear_cols: int):
    edges = []
    for r in range(kings_rows):
        for c in range(clear_cols):
            if c < clear_cols - 1:
                edges.append((EDGE_TYPE_H, r, c))
            if r < kings_rows - 1:
                edges.append((EDGE_TYPE_V, r, c))
            if r < kings_rows - 1 and c < clear_cols - 1:
                edges.append((EDGE_TYPE_DSE, r, c))
            if r < kings_rows - 1 and c > 0:
                edges.append((EDGE_TYPE_DSW, r, c))
    return edges


def make_pattern_target(pattern_cfg, rows, cols):
    row_texts = pattern_cfg["rows_text"]
    top = int(pattern_cfg.get("top", 0))
    left = int(pattern_cfg.get("left", 0))
    height = len(row_texts)
    width = len(row_texts[0]) if row_texts else 0
    if height == 0 or width == 0:
        raise ValueError("pattern rows_text must be non-empty")
    if any(len(row) != width for row in row_texts):
        raise ValueError("all pattern rows_text entries must have the same width")
    if top < 0 or left < 0 or top + height > rows or left + width > cols:
        raise ValueError("pattern placement is outside the requested grid")

    target = [-1 for _ in range(rows * cols)]
    for local_r, row_text in enumerate(row_texts):
        for local_c, ch in enumerate(row_text):
            idx = (top + local_r) * cols + (left + local_c)
            if ch == "#":
                target[idx] = 1
            elif ch == ".":
                target[idx] = -1
            else:
                raise ValueError("unsupported pattern character {!r}".format(ch))
    return target


def build_pattern_matrix(target, rows, cols):
    n = rows * cols
    W = [[0 for _ in range(n)] for _ in range(n)]
    logical_edges = []
    for r in range(rows):
        for c in range(cols):
            i = r * cols + c
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr == 0 and dc == 0:
                        continue
                    rr = r + dr
                    cc = c + dc
                    if rr < 0 or rr >= rows or cc < 0 or cc >= cols:
                        continue
                    j = rr * cols + cc
                    if i < j:
                        # Reference script uses edge_sum += J*s_j and feeds -edge_sum
                        # into the tanh path, so J=-target_i*target_j stabilizes target.
                        sign = -int(target[i] * target[j])
                        W[i][j] = sign
                        W[j][i] = sign
                        logical_edges.append((i, j, 1, sign))
    return W, logical_edges


def build_local_qubo_problem(problem_cfg, kings_rows, kings_cols):
    rows = int(problem_cfg.get("rows", 10))
    cols = int(problem_cfg.get("cols", 10))
    if rows < 1 or rows > kings_rows or cols < 1 or cols > kings_cols:
        raise ValueError("local_qubo rows/cols must fit inside the hardware grid")

    target_seed = int(problem_cfg.get("target_seed", 20260807))
    edge_strength = float(problem_cfg.get("edge_strength", 1.0))
    bias_strength = float(problem_cfg.get("bias_strength", 0.25))
    if edge_strength <= 0:
        raise ValueError("local_qubo edge_strength must be positive")
    if bias_strength < 0:
        raise ValueError("local_qubo bias_strength must be non-negative")

    edge_py_code = quantize_to_int(1.0, 7)
    edge_prob_code = rtl_prob_code_from_python_code(edge_py_code)
    bias_py_code = quantize_to_int(min(1.0, bias_strength / edge_strength), 7)
    bias_prob_code = rtl_prob_code_from_python_code(bias_py_code)

    rng = random.Random(target_seed)
    num_logical = rows * cols
    target_spins = [1 if rng.randrange(2) else -1 for _ in range(num_logical)]
    mapping = {}
    physical_nodes = []
    for r in range(rows):
        for c in range(cols):
            logical = r * cols + c
            q = r * kings_cols + c
            mapping[logical] = [q]
            physical_nodes.append(q)

    phys_to_idx = {q: idx for idx, q in enumerate(physical_nodes)}
    prob = [[0 for _ in range(num_logical)] for _ in range(num_logical)]
    sign = [[0 for _ in range(num_logical)] for _ in range(num_logical)]
    logical_edges = []
    logical_edge_signs = []

    for r in range(rows):
        for c in range(cols):
            a = r * cols + c
            for dr, dc in ((0, 1), (1, 0)):
                rr = r + dr
                cc = c + dc
                if rr >= rows or cc >= cols:
                    continue
                b = rr * cols + cc
                q_a = mapping[a][0]
                q_b = mapping[b][0]
                ia = phys_to_idx[q_a]
                ib = phys_to_idx[q_b]
                hw_sign = 1 if (target_spins[a] * target_spins[b]) > 0 else 0
                sign_int = 1 if hw_sign else -1
                prob[ia][ib] = edge_prob_code
                prob[ib][ia] = edge_prob_code
                sign[ia][ib] = hw_sign
                sign[ib][ia] = hw_sign
                logical_edges.append((a, b, edge_prob_code + 1))
                logical_edge_signs.append(sign_int)

    bias_prob = [bias_prob_code for _ in range(num_logical)]
    bias_sign = [1 if spin > 0 else 0 for spin in target_spins]
    target_energy = -sum(weight for _, _, weight in logical_edges)
    if bias_prob_code > 0:
        target_energy -= (bias_prob_code + 1) * num_logical

    return {
        "mapping": mapping,
        "physical_nodes": physical_nodes,
        "phys_to_idx": phys_to_idx,
        "prob": prob,
        "sign": sign,
        "logical_edges": logical_edges,
        "logical_edge_signs": logical_edge_signs,
        "target_spins": target_spins,
        "bias_prob": bias_prob,
        "bias_sign": bias_sign,
        "target_energy": target_energy,
    }


def make_seed(rng: random.Random):
    seed = rng.getrandbits(32)
    return seed if seed != 0 else 1


def make_randrange_seed(rng: random.Random):
    seed = rng.randrange(1, 2**32)
    return seed if seed != 0 else 1


def build_tile_seeds(num_runs, seed_master_start, seed_master_step, seed_rows, seed_cols):
    tile_seeds = []
    global_seeds = []
    for run_idx in range(num_runs):
        seed_master = seed_master_start + run_idx * seed_master_step
        seed_rng = random.Random(seed_master)
        global_seeds.append(make_seed(seed_rng))
        tile_seeds.append([make_seed(seed_rng) for _ in range(seed_rows * seed_cols)])
    return tile_seeds, global_seeds


def build_node_data(physical_nodes, num_runs, seed_master_start, seed_master_step, run_seed, seed_rows, seed_cols):
    init_spins = []
    tile_seeds, global_seeds = build_tile_seeds(num_runs, seed_master_start, seed_master_step, seed_rows, seed_cols)
    for run_idx in range(num_runs):
        spin_rng = random.Random(run_seed + run_idx)
        init_spins.append([1 if spin_rng.randrange(2) else 0 for _ in physical_nodes])
    return tile_seeds, init_spins, global_seeds


def build_maxcut_node_data(physical_nodes, num_runs, seed_master_start, seed_master_step, run_seed, seed_rows, seed_cols):
    tile_seeds = []
    init_spins = []
    global_seeds = []

    for run_idx in range(num_runs):
        seed_master = seed_master_start + run_idx * seed_master_step
        tile_rng = random.Random(seed_master)
        run_tile_seeds = [make_randrange_seed(tile_rng) for _ in range(seed_rows * seed_cols)]
        init_rng = random.Random(seed_master ^ 0x5A171234)

        run_init_spins = []
        for q in physical_nodes:
            run_init_spins.append(init_rng.randrange(0, 2))

        tile_seeds.append(run_tile_seeds)
        init_spins.append(run_init_spins)
        # This value is a run label for logs in the unified TB; shared tile
        # LFSR seeds above are what the hardware actually receives.
        global_seeds.append(make_seed(random.Random(run_seed + run_idx)))

    return tile_seeds, init_spins, global_seeds


def nearest_i0_level(i0_table, target_i0):
    return min(i0_table, key=lambda item: (abs(item[1] - target_i0), item[0]))[0]


def i0_value_to_level(i0_cfg, i0_table, value, i0_end):
    if i0_table is not None:
        return nearest_i0_level(i0_table, value)
    return quantize_to_int(value / i0_end, 6)


def build_i0_levels(run_cfg, spec_path):
    num_levels = int(run_cfg.get("num_i0_levels", 16))
    if num_levels < 1 or num_levels > 64 or num_levels % 4 != 0:
        raise ValueError("num_i0_levels must be a multiple of 4 in [1, 64]")
    i0_cfg = run_cfg.get("i0", {"mode": "linear", "start": 0.5, "end": 6.0})
    i0_end = float(i0_cfg.get("end", 6.0))
    i0_table = None
    if "table" in i0_cfg:
        i0_table = load_i0_table(resolve_path(spec_path, i0_cfg["table"]))
    mode = i0_cfg.get("mode", "linear")
    if mode == "fixed":
        level = i0_value_to_level(i0_cfg, i0_table, float(i0_cfg.get("value", 1.0)), i0_end)
        return [level for _ in range(num_levels)]
    if mode != "linear":
        raise ValueError(f"unsupported i0 mode {mode!r}")
    start = float(i0_cfg.get("start", 0.5))
    end = float(i0_cfg.get("end", 6.0))
    levels = []
    for idx in range(num_levels):
        ratio = 0.0 if num_levels == 1 else idx / (num_levels - 1)
        value = start + (end - start) * ratio
        levels.append(i0_value_to_level(i0_cfg, i0_table, value, end))
    return levels


def build_intervals(run_cfg, num_levels):
    num_sweeps = int(run_cfg.get("num_sweeps", num_levels * int(run_cfg.get("interval_per_level", 1))))
    if num_sweeps < num_levels:
        raise ValueError("num_sweeps must be >= num_i0_levels")
    intervals = [0 for _ in range(num_levels)]
    for sweep in range(num_sweeps):
        level = round((num_levels - 1) * sweep / max(1, num_sweeps - 1))
        intervals[level] += 1
    if len(intervals) % 2 != 0:
        raise ValueError("number of sweep intervals must be even")
    return num_sweeps, intervals


def chain_arrays(mapping, phys_to_idx):
    starts = [0]
    entries = []
    for logical in range(len(mapping)):
        entries.extend(phys_to_idx[q] for q in mapping[logical])
        starts.append(len(entries))
    return starts, entries


def sv_assign(name, values, fmt=str):
    lines = []
    for idx, value in enumerate(values):
        lines.append(f"        {name}[{idx}] = {fmt(value)};")
    return lines


def sv_bit(value):
    return "1'b1" if value else "1'b0"


def problem_from_spec(spec_path: Path, spec):
    kind = spec["kind"]
    inputs = spec.get("inputs", {})
    hw = spec.get("hardware", {})
    run = spec.get("run", {})
    kings_rows = int(hw.get("kings_rows", 20))
    kings_cols = int(hw.get("kings_cols", 19))
    num_runs = int(run.get("num_runs", 1))
    rtl_rows = int(hw.get("rtl_rows", kings_rows))
    rtl_cols = int(hw.get("rtl_cols", kings_cols))
    seed_rows = (rtl_rows + 1) // 2
    seed_cols = (rtl_cols + 1) // 2

    if kind == "maxcut":
        W = load_matrix(resolve_path(spec_path, inputs["weights"]))
        num_logical = len(W)
        mapping = load_mapping(resolve_path(spec_path, inputs["mapping"]), num_logical)
        logical_prob, logical_sign = normalize_unsigned_weights(W)
        target_spins = [1 for _ in range(num_logical)]
        logical_edge_signs = []
        bias_prob = None
        bias_sign = None
        logical_edges = [
            (i, j, int(round(abs(W[i][j]))))
            for i in range(num_logical)
            for j in range(i + 1, num_logical)
            if W[i][j] != 0
        ]
        logical_edge_signs = [1 for _ in logical_edges]
        clauses = []
        num_variables = 0
        lits_per_clause = 0
    elif kind == "pattern_maxcut":
        pattern_cfg = spec["pattern"]
        kings_rows = int(pattern_cfg.get("grid_rows", kings_rows))
        kings_cols = int(pattern_cfg.get("grid_cols", kings_cols))
        num_logical = kings_rows * kings_cols
        target_spins = make_pattern_target(pattern_cfg, kings_rows, kings_cols)
        W, signed_logical_edges = build_pattern_matrix(target_spins, kings_rows, kings_cols)
        mapping = {idx: [idx] for idx in range(num_logical)}
        logical_prob, logical_sign = normalize_signed_coupling(W)
        bias_prob = None
        bias_sign = None
        logical_edges = [(a, b, weight) for a, b, weight, _ in signed_logical_edges]
        logical_edge_signs = [sign for _, _, _, sign in signed_logical_edges]
        clauses = []
        num_variables = 0
        lits_per_clause = 0
    elif kind == "local_qubo":
        local_qubo = build_local_qubo_problem(spec["problem"], kings_rows, kings_cols)
        W = []
        num_logical = len(local_qubo["target_spins"])
        mapping = local_qubo["mapping"]
        logical_prob = []
        logical_sign = []
        bias_prob = local_qubo["bias_prob"]
        bias_sign = local_qubo["bias_sign"]
        logical_edges = local_qubo["logical_edges"]
        logical_edge_signs = local_qubo["logical_edge_signs"]
        target_spins = local_qubo["target_spins"]
        clauses = []
        num_variables = num_logical
        lits_per_clause = 0
    elif kind == "ksat":
        num_variables = int(spec["num_variables"])
        lits_per_clause = int(spec.get("lits_per_clause", 3))
        clauses = load_clauses(resolve_path(spec_path, inputs["clauses"]), num_variables, lits_per_clause)
        num_logical = int(spec.get("num_logical", num_variables + len(clauses)))
        W = load_matrix(resolve_path(spec_path, inputs["j"]), num_logical)
        logical_bias = load_bias(resolve_path(spec_path, inputs["bias"]), num_logical)
        mapping = load_mapping(resolve_path(spec_path, inputs["mapping"]), num_logical)
        logical_prob, logical_sign = normalize_signed_coupling(W)
        logical_edges = []
        logical_edge_signs = []
        target_spins = [1 for _ in range(num_logical)]
        max_bias = max(abs(x) for x in logical_bias) or 1
        physical_nodes_tmp = sorted({q for chain in mapping.values() for q in chain})
        phys_to_logical = {}
        for logical, chain in mapping.items():
            for q in chain:
                phys_to_logical[q] = logical
        bias_prob = []
        bias_sign = []
        for q in physical_nodes_tmp:
            bias_value = logical_bias[phys_to_logical[q]]
            py_code = quantize_to_int(abs(bias_value) / max_bias, 7)
            bias_prob.append(rtl_prob_code_from_python_code(py_code))
            bias_sign.append(1 if bias_value >= 0 else 0)
    else:
        raise ValueError(f"unsupported problem kind {kind!r}")

    if kind == "maxcut":
        physical_nodes, phys_to_idx, prob, sign = build_maxcut_physical_edges_split(W, mapping, kings_cols)
    elif kind == "local_qubo":
        physical_nodes = local_qubo["physical_nodes"]
        phys_to_idx = local_qubo["phys_to_idx"]
        prob = local_qubo["prob"]
        sign = local_qubo["sign"]
    else:
        physical_nodes, phys_to_idx, prob, sign = build_physical_edges(
            logical_prob, logical_sign, mapping, kings_cols
        )
    if kind == "ksat":
        # Reorder physical bias arrays to match sorted active physical node order.
        logical_bias = load_bias(resolve_path(spec_path, inputs["bias"]), num_logical)
        max_bias = max(abs(x) for x in logical_bias) or 1
        phys_to_logical = {}
        for logical, chain in mapping.items():
            for q in chain:
                phys_to_logical[q] = logical
        bias_prob = []
        bias_sign = []
        for q in physical_nodes:
            bias_value = logical_bias[phys_to_logical[q]]
            py_code = quantize_to_int(abs(bias_value) / max_bias, 7)
            bias_prob.append(rtl_prob_code_from_python_code(py_code))
            bias_sign.append(1 if bias_value >= 0 else 0)
    elif kind != "local_qubo":
        bias_prob = [0 for _ in physical_nodes]
        bias_sign = [1 for _ in physical_nodes]

    config_edges = build_config_edges(physical_nodes, prob, sign, kings_cols)
    clear_cols = min(kings_cols + 1, rtl_cols)
    clear_edges = build_clear_edges(kings_rows, clear_cols)
    if kind == "maxcut":
        tile_seeds, init_spins, global_seeds = build_maxcut_node_data(
            physical_nodes,
            num_runs,
            int(run.get("seed_master_start", run.get("seed_master", 2461))),
            int(run.get("seed_master_step", 1)),
            int(run.get("run_seed", 314592)),
            seed_rows,
            seed_cols,
        )
    else:
        tile_seeds, init_spins, global_seeds = build_node_data(
            physical_nodes,
            num_runs,
            int(run.get("seed_master_start", run.get("seed_master", 2461))),
            int(run.get("seed_master_step", 10)),
            int(run.get("run_seed", 314592)),
            seed_rows,
            seed_cols,
        )
    i0_levels = build_i0_levels(run, spec_path)
    num_sweeps, intervals = build_intervals(run, len(i0_levels))
    max_neighbors = max(sum(1 for p in row if p > 0) for row in prob) if prob else 0
    if max_neighbors > 8:
        raise ValueError(f"generated physical problem has degree {max_neighbors}, exceeds RTL limit 8")
    chain_start, chain_phys_idx = chain_arrays(mapping, phys_to_idx)
    max_flat = max((kings_coord(q, kings_cols)[0] * rtl_cols) +
                   kings_coord(q, kings_cols)[1] for q in physical_nodes)
    snapshot_width = int(spec.get("snapshot_width", RTL_SNAPSHOT_WIDTH))
    snapshot_pages = int(math.ceil((max_flat + 1) / float(snapshot_width)))

    return {
        "name": spec["name"],
        "kind": kind,
        "num_logical": num_logical,
        "num_variables": num_variables,
        "num_clauses": len(clauses),
        "lits_per_clause": lits_per_clause,
        "kings_rows": kings_rows,
        "kings_cols": kings_cols,
        "rtl_rows": rtl_rows,
        "rtl_cols": rtl_cols,
        "seed_rows": seed_rows,
        "seed_cols": seed_cols,
        "physical_nodes": physical_nodes,
        "phys_to_idx": phys_to_idx,
        "config_edges": config_edges,
        "clear_edges": clear_edges,
        "tile_seeds": tile_seeds,
        "init_spins": init_spins,
        "global_seeds": global_seeds,
        "bias_prob": bias_prob,
        "bias_sign": bias_sign,
        "chain_start": chain_start,
        "chain_phys_idx": chain_phys_idx,
        "logical_edges": logical_edges,
        "logical_edge_signs": logical_edge_signs,
        "target_spins": target_spins,
        "clauses": clauses,
        "i0_levels": i0_levels,
        "intervals": intervals,
        "num_sweeps": num_sweeps,
        "num_majority": int(run.get("num_majority", 5)),
        "num_runs": num_runs,
        "progress_print_step": int(run.get("progress_print_step", 500 if kind == "maxcut" else 50)),
        "min_pass_score": int(spec.get("pass", {}).get("min", 0)),
        "min_pattern_matches": int(math.ceil(float(spec.get("pass", {}).get(
            "pattern_acc", spec.get("pass", {}).get("target_acc", 0.99))) * num_logical)),
        "snapshot_pages": snapshot_pages,
        "max_neighbors": max_neighbors,
        "total_weight": sum(w for _, _, w in logical_edges),
        "target_energy": int(local_qubo["target_energy"]) if kind == "local_qubo" else 0,
    }


def write_data_svh(path: Path, problem):
    physical_nodes = problem["physical_nodes"]
    lines = []
    lines.append("`ifndef TB_GENERATED_PROBLEM_DATA_SVH")
    lines.append("`define TB_GENERATED_PROBLEM_DATA_SVH")
    lines.append("// Generated by tb/problem_gen/gen_problem.py. Do not hand-edit.")
    lines.append(f"localparam int unsigned PROBLEM_KIND_MAXCUT = 0;")
    lines.append(f"localparam int unsigned PROBLEM_KIND_KSAT = 1;")
    lines.append(f"localparam int unsigned PROBLEM_KIND_PATTERN_MAXCUT = 2;")
    lines.append(f"localparam int unsigned PROBLEM_KIND_LOCAL_QUBO = 3;")
    lines.append(f"localparam int unsigned PROBLEM_KIND = PROBLEM_KIND_{problem['kind'].upper()};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_LOGICAL = {problem['num_logical']};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_VARIABLES = {problem['num_variables']};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_CLAUSES = {problem['num_clauses']};")
    lines.append(f"localparam int unsigned PROBLEM_LITS_PER_CLAUSE = {problem['lits_per_clause']};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_PHYSICAL = {len(physical_nodes)};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_CONFIG_EDGES = {len(problem['config_edges'])};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_CLEAR_EDGES = {len(problem['clear_edges'])};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_CHAIN_ENTRIES = {len(problem['chain_phys_idx'])};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_LOGICAL_EDGES = {len(problem['logical_edges'])};")
    lines.append("localparam int unsigned PROBLEM_NUM_LOGICAL_EDGES_ALLOC = (PROBLEM_NUM_LOGICAL_EDGES == 0) ? 1 : PROBLEM_NUM_LOGICAL_EDGES;")
    lines.append(f"localparam int unsigned PROBLEM_NUM_SEED_RUNS = {problem['num_runs']};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_I0_LEVELS = {len(problem['i0_levels'])};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_SWEEPS = {problem['num_sweeps']};")
    lines.append(f"localparam int unsigned PROBLEM_NUM_MAJORITY = {problem['num_majority']};")
    lines.append(f"localparam int unsigned PROBLEM_MIN_PASS_SCORE = {problem['min_pass_score']};")
    lines.append(f"localparam int unsigned PROBLEM_PROGRESS_PRINT_STEP = {problem['progress_print_step']};")
    lines.append(f"localparam int unsigned PROBLEM_SNAPSHOT_PAGES = {problem['snapshot_pages']};")
    lines.append(f"localparam int unsigned PROBLEM_TOTAL_LOGICAL_WEIGHT = {problem['total_weight']};")
    lines.append(f"localparam int unsigned PROBLEM_MIN_PATTERN_MATCHES = {problem['min_pattern_matches']};")
    lines.append(f"localparam int signed PROBLEM_TARGET_ENERGY = {problem['target_energy']};")
    lines.append(f"localparam int unsigned PROBLEM_SEED_ROWS = {problem['seed_rows']};")
    lines.append(f"localparam int unsigned PROBLEM_SEED_COLS = {problem['seed_cols']};")
    lines.append("localparam int unsigned PROBLEM_NUM_TILE_SEEDS = PROBLEM_SEED_ROWS * PROBLEM_SEED_COLS;")
    lines.append("")
    lines.append("logic [NODE_TARGET_ROW_WIDTH-1:0] problem_phys_row [PROBLEM_NUM_PHYSICAL];")
    lines.append("logic [NODE_TARGET_COL_WIDTH-1:0] problem_phys_col [PROBLEM_NUM_PHYSICAL];")
    lines.append("logic [31:0] problem_global_seed [PROBLEM_NUM_SEED_RUNS];")
    lines.append("logic [31:0] problem_tile_seed [PROBLEM_NUM_SEED_RUNS][PROBLEM_NUM_TILE_SEEDS];")
    lines.append("logic problem_node_init_spin [PROBLEM_NUM_SEED_RUNS][PROBLEM_NUM_PHYSICAL];")
    lines.append("logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] problem_node_bias_prob [PROBLEM_NUM_PHYSICAL];")
    lines.append("logic problem_node_bias_sign [PROBLEM_NUM_PHYSICAL];")
    lines.append("logic [EDGE_TYPE_WIDTH-1:0] problem_edge_type [PROBLEM_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TARGET_ROW_WIDTH-1:0] problem_edge_row [PROBLEM_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TARGET_COL_WIDTH-1:0] problem_edge_col [PROBLEM_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] problem_edge_prob [PROBLEM_NUM_CONFIG_EDGES];")
    lines.append("logic problem_edge_sign [PROBLEM_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TYPE_WIDTH-1:0] problem_clear_edge_type [PROBLEM_NUM_CLEAR_EDGES];")
    lines.append("logic [EDGE_TARGET_ROW_WIDTH-1:0] problem_clear_edge_row [PROBLEM_NUM_CLEAR_EDGES];")
    lines.append("logic [EDGE_TARGET_COL_WIDTH-1:0] problem_clear_edge_col [PROBLEM_NUM_CLEAR_EDGES];")
    lines.append("int unsigned problem_chain_start [PROBLEM_NUM_LOGICAL + 1];")
    lines.append("int unsigned problem_chain_phys_idx [PROBLEM_NUM_CHAIN_ENTRIES];")
    lines.append("int unsigned problem_logical_edge_a [PROBLEM_NUM_LOGICAL_EDGES_ALLOC];")
    lines.append("int unsigned problem_logical_edge_b [PROBLEM_NUM_LOGICAL_EDGES_ALLOC];")
    lines.append("int unsigned problem_logical_edge_weight [PROBLEM_NUM_LOGICAL_EDGES_ALLOC];")
    lines.append("int signed problem_logical_edge_sign [PROBLEM_NUM_LOGICAL_EDGES_ALLOC];")
    lines.append("logic problem_target_spin [PROBLEM_NUM_LOGICAL];")
    lines.append("localparam int unsigned PROBLEM_NUM_CLAUSE_LITS = PROBLEM_NUM_CLAUSES * PROBLEM_LITS_PER_CLAUSE;")
    lines.append("localparam int unsigned PROBLEM_NUM_CLAUSE_LITS_ALLOC = (PROBLEM_NUM_CLAUSE_LITS == 0) ? 1 : PROBLEM_NUM_CLAUSE_LITS;")
    lines.append("int unsigned problem_clause_var [PROBLEM_NUM_CLAUSE_LITS_ALLOC];")
    lines.append("logic problem_clause_pos [PROBLEM_NUM_CLAUSE_LITS_ALLOC];")
    lines.append("logic [I0_LEVEL_WIDTH-1:0] problem_i0_level [PROBLEM_NUM_I0_LEVELS];")
    lines.append("logic [SWEEP_INTERVAL_WIDTH-1:0] problem_sweep_interval [PROBLEM_NUM_I0_LEVELS];")
    lines.append("")
    lines.append("task automatic load_problem_data();")
    lines.extend(sv_assign("problem_phys_row", [kings_coord(q, problem["kings_cols"])[0] for q in physical_nodes]))
    lines.extend(sv_assign("problem_phys_col", [kings_coord(q, problem["kings_cols"])[1] for q in physical_nodes]))
    for run_idx, seed in enumerate(problem["global_seeds"]):
        lines.append(f"        problem_global_seed[{run_idx}] = 32'h{seed:08x};")
    for run_idx in range(problem["num_runs"]):
        for idx, seed in enumerate(problem["tile_seeds"][run_idx]):
            lines.append(f"        problem_tile_seed[{run_idx}][{idx}] = 32'h{seed:08x};")
        for idx, spin in enumerate(problem["init_spins"][run_idx]):
            lines.append(f"        problem_node_init_spin[{run_idx}][{idx}] = {sv_bit(spin)};")
    lines.extend(sv_assign("problem_node_bias_prob", problem["bias_prob"]))
    lines.extend(sv_assign("problem_node_bias_sign", problem["bias_sign"], sv_bit))
    for idx, (edge_type, row, col, prob, sign) in enumerate(problem["config_edges"]):
        lines.append(f"        problem_edge_type[{idx}] = {edge_type};")
        lines.append(f"        problem_edge_row[{idx}] = {row};")
        lines.append(f"        problem_edge_col[{idx}] = {col};")
        lines.append(f"        problem_edge_prob[{idx}] = {prob};")
        lines.append(f"        problem_edge_sign[{idx}] = {sv_bit(sign)};")
    for idx, (edge_type, row, col) in enumerate(problem["clear_edges"]):
        lines.append(f"        problem_clear_edge_type[{idx}] = {edge_type};")
        lines.append(f"        problem_clear_edge_row[{idx}] = {row};")
        lines.append(f"        problem_clear_edge_col[{idx}] = {col};")
    lines.extend(sv_assign("problem_chain_start", problem["chain_start"]))
    lines.extend(sv_assign("problem_chain_phys_idx", problem["chain_phys_idx"]))
    for idx, (a, b, weight) in enumerate(problem["logical_edges"]):
        lines.append(f"        problem_logical_edge_a[{idx}] = {a};")
        lines.append(f"        problem_logical_edge_b[{idx}] = {b};")
        lines.append(f"        problem_logical_edge_weight[{idx}] = {weight};")
        lines.append(f"        problem_logical_edge_sign[{idx}] = {problem['logical_edge_signs'][idx]};")
    lines.extend(sv_assign("problem_target_spin", [spin > 0 for spin in problem["target_spins"]], sv_bit))
    flat_clauses = [item for clause in problem["clauses"] for item in clause]
    for idx, (var, pos) in enumerate(flat_clauses):
        lines.append(f"        problem_clause_var[{idx}] = {var};")
        lines.append(f"        problem_clause_pos[{idx}] = {sv_bit(pos)};")
    lines.extend(sv_assign("problem_i0_level", problem["i0_levels"]))
    lines.extend(sv_assign("problem_sweep_interval", problem["intervals"]))
    lines.append("endtask")
    lines.append("`endif")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_score_svh(path: Path, problem):
    if problem["kind"] == "maxcut":
        body = maxcut_score_template()
    elif problem["kind"] == "pattern_maxcut":
        body = pattern_maxcut_score_template()
    elif problem["kind"] == "local_qubo":
        body = local_qubo_score_template()
    elif problem["kind"] == "ksat":
        body = ksat_score_template()
    else:
        raise ValueError(f"unsupported scoring kind {problem['kind']}")
    path.write_text(body, encoding="ascii")


def maxcut_score_template():
    return r'''`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
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
'''


def pattern_maxcut_score_template():
    return r'''`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
`define TB_GENERATED_PROBLEM_SCORE_SVH
// Generated signed-pattern MaxCut scoring hooks for tb_run_problem.sv.

int unsigned problem_live_best_satisfied_edges;
int unsigned problem_live_best_pattern_matches;
int unsigned problem_live_best_sweep;
int unsigned problem_live_best_cycle;
int unsigned problem_live_final_satisfied_edges;
int unsigned problem_live_final_unsatisfied_edges;
int unsigned problem_live_final_pattern_matches;
int unsigned problem_live_final_cycle;
int unsigned problem_live_final_broken_chains;
int unsigned problem_live_sample_count;
integer problem_history_fd;

task automatic problem_score_all_runs_init();
    begin
    end
endtask

task automatic problem_score_pattern(
    input  bit use_live_spins,
    input  bit print_spins,
    output int unsigned satisfied_edges,
    output int unsigned unsatisfied_edges,
    output int unsigned pattern_matches,
    output int unsigned broken_chain_count
);
    logic logical_spin [PROBLEM_NUM_LOGICAL];
    logic phys_spin;
    int signed chain_sum;
    int signed chain_sum_abs;
    int unsigned chain_len;
    int unsigned direct_matches;
    int unsigned flipped_matches;
    int signed spin_a;
    int signed spin_b;
    begin
        broken_chain_count = 0;
        direct_matches = 0;
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
            if (logical_spin[logical] == problem_target_spin[logical]) begin
                direct_matches++;
            end
        end

        flipped_matches = PROBLEM_NUM_LOGICAL - direct_matches;
        pattern_matches = (direct_matches > flipped_matches) ? direct_matches : flipped_matches;

        satisfied_edges = 0;
        for (int edge_idx = 0; edge_idx < PROBLEM_NUM_LOGICAL_EDGES; edge_idx++) begin
            spin_a = logical_spin[problem_logical_edge_a[edge_idx]] ? 1 : -1;
            spin_b = logical_spin[problem_logical_edge_b[edge_idx]] ? 1 : -1;
            if ((problem_logical_edge_sign[edge_idx] * spin_a * spin_b) < 0) begin
                satisfied_edges++;
            end
        end
        unsatisfied_edges = PROBLEM_NUM_LOGICAL_EDGES - satisfied_edges;

        if (print_spins) begin
            $display("[RUN_PROBLEM_PATTERN] satisfied_edges=%0d/%0d pattern_matches=%0d/%0d broken_chains=%0d/%0d",
                     satisfied_edges, PROBLEM_NUM_LOGICAL_EDGES,
                     pattern_matches, PROBLEM_NUM_LOGICAL,
                     broken_chain_count, PROBLEM_NUM_LOGICAL);
        end
    end
endtask

task automatic problem_score_init(input int unsigned run_idx);
    begin
        problem_live_best_satisfied_edges = 0;
        problem_live_best_pattern_matches = 0;
        problem_live_best_sweep = 0;
        problem_live_best_cycle = 0;
        problem_live_final_satisfied_edges = 0;
        problem_live_final_unsatisfied_edges = PROBLEM_NUM_LOGICAL_EDGES;
        problem_live_final_pattern_matches = 0;
        problem_live_final_cycle = 0;
        problem_live_final_broken_chains = 0;
        problem_live_sample_count = 0;
        problem_history_fd = $fopen($sformatf("sim_run_problem_pattern_run%0d_history.csv", run_idx), "w");
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "run,sweep,cycles_since_run_start,satisfied_edges,unsatisfied_edges,best_satisfied_edges,pattern_matches,best_pattern_matches,best_sweep,best_cycle,broken_chains,i0_level,round,time");
        end
    end
endtask

task automatic problem_score_record(
    input int unsigned run_idx,
    input int unsigned sweep_idx,
    input int unsigned cycles_since_run_start,
    input bit force_print
);
    int unsigned satisfied_edges;
    int unsigned unsatisfied_edges;
    int unsigned pattern_matches;
    int unsigned broken_chain_count;
    bit improved;
    begin
        problem_score_pattern(1'b1, 1'b0, satisfied_edges, unsatisfied_edges,
                              pattern_matches, broken_chain_count);
        improved = (problem_live_sample_count == 0) ||
                   (pattern_matches > problem_live_best_pattern_matches) ||
                   ((pattern_matches == problem_live_best_pattern_matches) &&
                    (satisfied_edges > problem_live_best_satisfied_edges));
        if (improved) begin
            problem_live_best_satisfied_edges = satisfied_edges;
            problem_live_best_pattern_matches = pattern_matches;
            problem_live_best_sweep = sweep_idx + 1;
            problem_live_best_cycle = cycles_since_run_start;
        end
        problem_live_sample_count++;
        problem_live_final_satisfied_edges = satisfied_edges;
        problem_live_final_unsatisfied_edges = unsatisfied_edges;
        problem_live_final_pattern_matches = pattern_matches;
        problem_live_final_cycle = cycles_since_run_start;
        problem_live_final_broken_chains = broken_chain_count;

        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                      run_idx, sweep_idx + 1, cycles_since_run_start,
                      satisfied_edges, unsatisfied_edges, problem_live_best_satisfied_edges,
                      pattern_matches, problem_live_best_pattern_matches,
                      problem_live_best_sweep, problem_live_best_cycle,
                      broken_chain_count,
                      u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                      u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q, $time);
        end
        if (improved || force_print || (((sweep_idx + 1) % PROBLEM_PROGRESS_PRINT_STEP) == 0)) begin
            $display("[RUN_PROBLEM_PATTERN_SWEEP] run=%0d sweep=%0d cycles=%0d satisfied=%0d/%0d unsat=%0d pattern=%0d/%0d best_pattern=%0d/%0d best_sweep=%0d best_cycle=%0d broken=%0d i0=%0d round=%0d",
                     run_idx, sweep_idx + 1, cycles_since_run_start,
                     satisfied_edges, PROBLEM_NUM_LOGICAL_EDGES, unsatisfied_edges,
                     pattern_matches, PROBLEM_NUM_LOGICAL,
                     problem_live_best_pattern_matches, PROBLEM_NUM_LOGICAL,
                     problem_live_best_sweep, problem_live_best_cycle,
                     broken_chain_count,
                     u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                     u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
        end
    end
endtask

task automatic problem_score_final(input int unsigned run_idx);
    int unsigned snapshot_satisfied_edges;
    int unsigned snapshot_unsatisfied_edges;
    int unsigned snapshot_pattern_matches;
    int unsigned snapshot_broken;
    begin
        problem_score_pattern(1'b0, 1'b1, snapshot_satisfied_edges,
                              snapshot_unsatisfied_edges, snapshot_pattern_matches,
                              snapshot_broken);
        $display("[RUN_PROBLEM_PATTERN_RUN] run=%0d final_satisfied=%0d/%0d final_unsat=%0d final_pattern=%0d/%0d final_cycle=%0d best_pattern=%0d/%0d best_sweep=%0d best_cycle=%0d min_pattern=%0d",
                 run_idx, snapshot_satisfied_edges, PROBLEM_NUM_LOGICAL_EDGES,
                 snapshot_unsatisfied_edges, snapshot_pattern_matches, PROBLEM_NUM_LOGICAL,
                 problem_live_final_cycle, problem_live_best_pattern_matches,
                 PROBLEM_NUM_LOGICAL, problem_live_best_sweep, problem_live_best_cycle,
                 PROBLEM_MIN_PATTERN_MATCHES);
        if (snapshot_satisfied_edges != problem_live_final_satisfied_edges) begin
            error_count++;
            $error("[RUN_PROBLEM_PATTERN] live/snapshot satisfied-edge mismatch: live=%0d snapshot=%0d",
                   problem_live_final_satisfied_edges, snapshot_satisfied_edges);
        end
        if (snapshot_pattern_matches != problem_live_final_pattern_matches) begin
            error_count++;
            $error("[RUN_PROBLEM_PATTERN] live/snapshot pattern mismatch: live=%0d snapshot=%0d",
                   problem_live_final_pattern_matches, snapshot_pattern_matches);
        end
        if (snapshot_broken != problem_live_final_broken_chains) begin
            error_count++;
            $error("[RUN_PROBLEM_PATTERN] live/snapshot broken-chain mismatch: live=%0d snapshot=%0d",
                   problem_live_final_broken_chains, snapshot_broken);
        end
        if (problem_history_fd != 0) begin
            $fclose(problem_history_fd);
            problem_history_fd = 0;
        end
    end
endtask

function automatic bit problem_score_pass();
    problem_score_pass = (problem_live_best_pattern_matches >= PROBLEM_MIN_PATTERN_MATCHES);
endfunction

task automatic problem_score_all_runs_summary();
    begin
        $display("[RUN_PROBLEM_PATTERN_SUMMARY] best_pattern=%0d/%0d best_sweep=%0d best_cycle=%0d min_pattern=%0d best_satisfied=%0d/%0d",
                 problem_live_best_pattern_matches, PROBLEM_NUM_LOGICAL,
                 problem_live_best_sweep, problem_live_best_cycle,
                 PROBLEM_MIN_PATTERN_MATCHES,
                 problem_live_best_satisfied_edges, PROBLEM_NUM_LOGICAL_EDGES);
    end
endtask
`endif
'''


def local_qubo_score_template():
    return r'''`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
`define TB_GENERATED_PROBLEM_SCORE_SVH
// Generated planted local-QUBO scoring hooks for tb_run_problem.sv.

int signed problem_live_best_energy;
int signed problem_live_final_energy;
int signed problem_live_final_gap;
int unsigned problem_live_best_matches;
int unsigned problem_live_best_sweep;
int unsigned problem_live_best_cycle;
int unsigned problem_live_final_matches;
int unsigned problem_live_final_cycle;
int unsigned problem_live_sample_count;
integer problem_history_fd;

task automatic problem_score_all_runs_init();
    begin
    end
endtask

task automatic problem_score_local_qubo(
    input  bit use_live_spins,
    input  bit print_spins,
    output int signed energy,
    output int signed gap,
    output int unsigned target_matches
);
    logic logical_spin [PROBLEM_NUM_LOGICAL];
    logic phys_spin;
    int signed spin_i;
    int signed spin_a;
    int signed spin_b;
    int signed edge_sign;
    int signed bias_sign;
    int signed bias_weight;
    begin
        target_matches = 0;
        for (int logical = 0; logical < PROBLEM_NUM_LOGICAL; logical++) begin
            phys_spin = use_live_spins ?
                        physical_spin_live(problem_chain_phys_idx[problem_chain_start[logical]]) :
                        physical_spin_snapshot(problem_chain_phys_idx[problem_chain_start[logical]]);
            logical_spin[logical] = phys_spin;
            if (logical_spin[logical] == problem_target_spin[logical]) begin
                target_matches++;
            end
        end

        energy = 0;
        for (int edge_idx = 0; edge_idx < PROBLEM_NUM_LOGICAL_EDGES; edge_idx++) begin
            spin_a = logical_spin[problem_logical_edge_a[edge_idx]] ? 1 : -1;
            spin_b = logical_spin[problem_logical_edge_b[edge_idx]] ? 1 : -1;
            edge_sign = problem_logical_edge_sign[edge_idx];
            energy -= edge_sign * spin_a * spin_b * int'(problem_logical_edge_weight[edge_idx]);
        end

        for (int logical = 0; logical < PROBLEM_NUM_LOGICAL; logical++) begin
            spin_i = logical_spin[logical] ? 1 : -1;
            bias_sign = problem_node_bias_sign[logical] ? 1 : -1;
            bias_weight = (problem_node_bias_prob[logical] == 0) ? 0 :
                          (int'(problem_node_bias_prob[logical]) + 1);
            energy -= bias_sign * spin_i * bias_weight;
        end
        gap = energy - PROBLEM_TARGET_ENERGY;

        if (print_spins) begin
            $display("[RUN_PROBLEM_LOCAL_QUBO] energy=%0d target_energy=%0d gap=%0d target_matches=%0d/%0d",
                     energy, PROBLEM_TARGET_ENERGY, gap,
                     target_matches, PROBLEM_NUM_LOGICAL);
        end
    end
endtask

task automatic problem_score_init(input int unsigned run_idx);
    begin
        problem_live_best_energy = 32'sh7fffffff;
        problem_live_final_energy = 0;
        problem_live_final_gap = 0;
        problem_live_best_matches = 0;
        problem_live_best_sweep = 0;
        problem_live_best_cycle = 0;
        problem_live_final_matches = 0;
        problem_live_final_cycle = 0;
        problem_live_sample_count = 0;
        problem_history_fd = $fopen($sformatf("sim_run_problem_local_qubo_run%0d_history.csv", run_idx), "w");
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "run,sweep,cycles_since_run_start,energy,best_energy,gap,target_matches,best_matches,best_sweep,best_cycle,i0_level,round,time");
        end
    end
endtask

task automatic problem_score_record(
    input int unsigned run_idx,
    input int unsigned sweep_idx,
    input int unsigned cycles_since_run_start,
    input bit force_print
);
    int signed energy;
    int signed gap;
    int unsigned target_matches;
    bit improved;
    begin
        problem_score_local_qubo(1'b1, 1'b0, energy, gap, target_matches);
        improved = (problem_live_sample_count == 0) ||
                   (energy < problem_live_best_energy) ||
                   ((energy == problem_live_best_energy) &&
                    (target_matches > problem_live_best_matches));
        if (improved) begin
            problem_live_best_energy = energy;
            problem_live_best_matches = target_matches;
            problem_live_best_sweep = sweep_idx + 1;
            problem_live_best_cycle = cycles_since_run_start;
        end
        problem_live_sample_count++;
        problem_live_final_energy = energy;
        problem_live_final_gap = gap;
        problem_live_final_matches = target_matches;
        problem_live_final_cycle = cycles_since_run_start;

        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                      run_idx, sweep_idx + 1, cycles_since_run_start,
                      energy, problem_live_best_energy, gap,
                      target_matches, problem_live_best_matches,
                      problem_live_best_sweep, problem_live_best_cycle,
                      u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                      u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q, $time);
        end
        if (improved || force_print || (((sweep_idx + 1) % PROBLEM_PROGRESS_PRINT_STEP) == 0)) begin
            $display("[RUN_PROBLEM_LOCAL_QUBO_SWEEP] run=%0d sweep=%0d cycles=%0d energy=%0d best_energy=%0d gap=%0d target=%0d/%0d best_target=%0d/%0d best_sweep=%0d best_cycle=%0d i0=%0d round=%0d",
                     run_idx, sweep_idx + 1, cycles_since_run_start,
                     energy, problem_live_best_energy, gap,
                     target_matches, PROBLEM_NUM_LOGICAL,
                     problem_live_best_matches, PROBLEM_NUM_LOGICAL,
                     problem_live_best_sweep, problem_live_best_cycle,
                     u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                     u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
        end
    end
endtask

task automatic problem_score_final(input int unsigned run_idx);
    int signed snapshot_energy;
    int signed snapshot_gap;
    int unsigned snapshot_matches;
    begin
        problem_score_local_qubo(1'b0, 1'b1, snapshot_energy, snapshot_gap, snapshot_matches);
        $display("[RUN_PROBLEM_LOCAL_QUBO_RUN] run=%0d final_energy=%0d final_gap=%0d final_target=%0d/%0d final_cycle=%0d best_energy=%0d best_target=%0d/%0d best_sweep=%0d best_cycle=%0d min_target=%0d",
                 run_idx, snapshot_energy, snapshot_gap,
                 snapshot_matches, PROBLEM_NUM_LOGICAL,
                 problem_live_final_cycle, problem_live_best_energy,
                 problem_live_best_matches, PROBLEM_NUM_LOGICAL,
                 problem_live_best_sweep, problem_live_best_cycle,
                 PROBLEM_MIN_PATTERN_MATCHES);
        if (snapshot_energy != problem_live_final_energy) begin
            error_count++;
            $error("[RUN_PROBLEM_LOCAL_QUBO] live/snapshot energy mismatch: live=%0d snapshot=%0d",
                   problem_live_final_energy, snapshot_energy);
        end
        if (snapshot_matches != problem_live_final_matches) begin
            error_count++;
            $error("[RUN_PROBLEM_LOCAL_QUBO] live/snapshot target-match mismatch: live=%0d snapshot=%0d",
                   problem_live_final_matches, snapshot_matches);
        end
        if (problem_history_fd != 0) begin
            $fclose(problem_history_fd);
            problem_history_fd = 0;
        end
    end
endtask

function automatic bit problem_score_pass();
    problem_score_pass = (problem_live_best_matches >= PROBLEM_MIN_PATTERN_MATCHES);
endfunction

task automatic problem_score_all_runs_summary();
    begin
        $display("[RUN_PROBLEM_LOCAL_QUBO_SUMMARY] best_energy=%0d target_energy=%0d best_gap=%0d best_target=%0d/%0d best_sweep=%0d best_cycle=%0d min_target=%0d",
                 problem_live_best_energy, PROBLEM_TARGET_ENERGY,
                 problem_live_best_energy - PROBLEM_TARGET_ENERGY,
                 problem_live_best_matches, PROBLEM_NUM_LOGICAL,
                 problem_live_best_sweep, problem_live_best_cycle,
                 PROBLEM_MIN_PATTERN_MATCHES);
    end
endtask
`endif
'''


def ksat_score_template():
    return r'''`ifndef TB_GENERATED_PROBLEM_SCORE_SVH
`define TB_GENERATED_PROBLEM_SCORE_SVH
// Generated K-SAT scoring hooks for tb_run_problem.sv.

int unsigned problem_live_best_score;
int unsigned problem_live_min_unsatisfied;
int unsigned problem_live_first_success_sweep;
int unsigned problem_live_first_success_cycle;
int unsigned problem_live_final_score;
int unsigned problem_live_final_cycle;
int unsigned problem_live_final_unsatisfied;
int unsigned problem_live_final_broken_chains;
int unsigned problem_live_best_broken_chains;
int unsigned problem_success_count;
int unsigned problem_fastest_success_sweep;
int unsigned problem_fastest_success_cycle;
int unsigned problem_fastest_success_run;
int unsigned problem_run_first_success_sweep [PROBLEM_NUM_SEED_RUNS];
int unsigned problem_run_first_success_cycle [PROBLEM_NUM_SEED_RUNS];
int unsigned problem_run_best_score [PROBLEM_NUM_SEED_RUNS];
int unsigned problem_run_final_score [PROBLEM_NUM_SEED_RUNS];
integer problem_history_fd;

task automatic problem_score_all_runs_init();
    begin
        problem_success_count = 0;
        problem_fastest_success_sweep = 0;
        problem_fastest_success_cycle = 0;
        problem_fastest_success_run = 0;
        for (int run_idx = 0; run_idx < PROBLEM_NUM_SEED_RUNS; run_idx++) begin
            problem_run_first_success_sweep[run_idx] = 0;
            problem_run_first_success_cycle[run_idx] = 0;
            problem_run_best_score[run_idx] = 0;
            problem_run_final_score[run_idx] = 0;
        end
    end
endtask

task automatic problem_score_sat(
    input  bit use_live_spins,
    output int unsigned satisfied,
    output int unsigned unsatisfied,
    output int unsigned broken_chain_count
);
    logic logical_spin [PROBLEM_NUM_LOGICAL];
    logic phys_spin;
    int signed chain_sum;
    int signed chain_sum_abs;
    int unsigned chain_len;
    int unsigned lit_idx;
    bit clause_sat;
    bit lit_value;
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

        satisfied = 0;
        for (int clause_idx = 0; clause_idx < PROBLEM_NUM_CLAUSES; clause_idx++) begin
            clause_sat = 1'b0;
            for (int lit = 0; lit < PROBLEM_LITS_PER_CLAUSE; lit++) begin
                lit_idx = clause_idx * PROBLEM_LITS_PER_CLAUSE + lit;
                lit_value = logical_spin[problem_clause_var[lit_idx]];
                if (!problem_clause_pos[lit_idx]) begin
                    lit_value = !lit_value;
                end
                clause_sat = clause_sat || lit_value;
            end
            if (clause_sat) begin
                satisfied++;
            end
        end
        unsatisfied = PROBLEM_NUM_CLAUSES - satisfied;
    end
endtask

task automatic problem_score_init(input int unsigned run_idx);
    begin
        problem_live_best_score = 0;
        problem_live_min_unsatisfied = PROBLEM_NUM_CLAUSES;
        problem_live_first_success_sweep = 0;
        problem_live_first_success_cycle = 0;
        problem_live_final_score = 0;
        problem_live_final_cycle = 0;
        problem_live_final_unsatisfied = PROBLEM_NUM_CLAUSES;
        problem_live_final_broken_chains = 0;
        problem_live_best_broken_chains = 0;
        problem_history_fd = $fopen($sformatf("sim_run_problem_ksat_run%0d_history.csv", run_idx), "w");
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "run,sweep,cycles_since_run_start,satisfied,unsatisfied,best_satisfied,min_unsatisfied,first_success_sweep,first_success_cycle,broken_chains,best_broken_chains,i0_level,round,time");
        end
    end
endtask

task automatic problem_score_record(
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
        problem_score_sat(1'b1, satisfied, unsatisfied, broken_chain_count);
        improved = (satisfied > problem_live_best_score);
        if (improved) begin
            problem_live_best_score = satisfied;
            problem_live_min_unsatisfied = unsatisfied;
            problem_live_best_broken_chains = broken_chain_count;
        end
        if ((satisfied == PROBLEM_NUM_CLAUSES) && (problem_live_first_success_sweep == 0)) begin
            problem_live_first_success_sweep = sweep_idx + 1;
            problem_live_first_success_cycle = cycles_since_run_start;
        end
        problem_live_final_score = satisfied;
        problem_live_final_cycle = cycles_since_run_start;
        problem_live_final_unsatisfied = unsatisfied;
        problem_live_final_broken_chains = broken_chain_count;
        if (problem_history_fd != 0) begin
            $fdisplay(problem_history_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0t",
                      run_idx, sweep_idx + 1, cycles_since_run_start,
                      satisfied, unsatisfied,
                      problem_live_best_score, problem_live_min_unsatisfied,
                      problem_live_first_success_sweep, problem_live_first_success_cycle,
                      broken_chain_count,
                      problem_live_best_broken_chains,
                      u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                      u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q, $time);
        end
        if (improved || force_print || (problem_live_first_success_sweep == (sweep_idx + 1)) ||
            (((sweep_idx + 1) % PROBLEM_PROGRESS_PRINT_STEP) == 0)) begin
            $display("[RUN_PROBLEM_KSAT_SWEEP] run=%0d sweep=%0d cycles=%0d satisfied=%0d/%0d best=%0d first_success=%0d first_success_cycle=%0d broken=%0d i0=%0d round=%0d",
                     run_idx, sweep_idx + 1, cycles_since_run_start,
                     satisfied, PROBLEM_NUM_CLAUSES,
                     problem_live_best_score, problem_live_first_success_sweep,
                     problem_live_first_success_cycle,
                     broken_chain_count,
                     u_pbit_top.u_phase_ctrl_4color.i0_level_o,
                     u_pbit_top.u_phase_ctrl_4color.sweep_round_cnt_q);
        end
    end
endtask

task automatic problem_score_final(input int unsigned run_idx);
    int unsigned snapshot_satisfied;
    int unsigned snapshot_unsatisfied;
    int unsigned snapshot_broken;
    begin
        problem_score_sat(1'b0, snapshot_satisfied, snapshot_unsatisfied, snapshot_broken);
        problem_run_first_success_sweep[run_idx] = problem_live_first_success_sweep;
        problem_run_first_success_cycle[run_idx] = problem_live_first_success_cycle;
        problem_run_best_score[run_idx] = problem_live_best_score;
        problem_run_final_score[run_idx] = snapshot_satisfied;
        if (problem_live_best_score >= PROBLEM_MIN_PASS_SCORE) begin
            problem_success_count++;
        end
        if (problem_live_first_success_sweep != 0) begin
            if ((problem_fastest_success_sweep == 0) ||
                (problem_live_first_success_sweep < problem_fastest_success_sweep) ||
                ((problem_live_first_success_sweep == problem_fastest_success_sweep) &&
                 (problem_live_first_success_cycle < problem_fastest_success_cycle))) begin
                problem_fastest_success_sweep = problem_live_first_success_sweep;
                problem_fastest_success_cycle = problem_live_first_success_cycle;
                problem_fastest_success_run = run_idx;
            end
        end
        $display("[RUN_PROBLEM_KSAT_RUN] run=%0d best_satisfied=%0d/%0d first_success_sweep=%0d first_success_cycle=%0d final_satisfied=%0d/%0d final_unsatisfied=%0d final_cycle=%0d broken=%0d",
                 run_idx, problem_live_best_score, PROBLEM_NUM_CLAUSES,
                 problem_live_first_success_sweep, problem_live_first_success_cycle,
                 snapshot_satisfied, PROBLEM_NUM_CLAUSES, snapshot_unsatisfied,
                 problem_live_final_cycle, snapshot_broken);
        if (snapshot_satisfied != problem_live_final_score) begin
            error_count++;
            $error("[RUN_PROBLEM_KSAT] live/snapshot satisfied mismatch: live=%0d snapshot=%0d",
                   problem_live_final_score, snapshot_satisfied);
        end
        if (problem_history_fd != 0) begin
            $fclose(problem_history_fd);
            problem_history_fd = 0;
        end
    end
endtask

function automatic bit problem_score_pass();
    problem_score_pass = (problem_success_count > 0);
endfunction

task automatic problem_score_all_runs_summary();
    begin
        $display("[RUN_PROBLEM_KSAT_SUMMARY] success_count=%0d/%0d fastest_run=%0d fastest_first_success_sweep=%0d fastest_first_success_cycle=%0d",
                 problem_success_count, PROBLEM_NUM_SEED_RUNS,
                 problem_fastest_success_run, problem_fastest_success_sweep,
                 problem_fastest_success_cycle);
        for (int run_idx = 0; run_idx < PROBLEM_NUM_SEED_RUNS; run_idx++) begin
            $display("[RUN_PROBLEM_KSAT_SUMMARY] run=%0d first_success_sweep=%0d first_success_cycle=%0d best_satisfied=%0d/%0d final_satisfied=%0d/%0d",
                     run_idx, problem_run_first_success_sweep[run_idx],
                     problem_run_first_success_cycle[run_idx],
                     problem_run_best_score[run_idx], PROBLEM_NUM_CLAUSES,
                     problem_run_final_score[run_idx], PROBLEM_NUM_CLAUSES);
        end
    end
endtask
`endif
'''


def write_filelist(path: Path):
    lines = [
        "+incdir+common",
        "+incdir+new_version",
        "+incdir+tb",
        "+incdir+tb/generated",
        "./common/dff_sets.sv",
        "./common/one_counter.sv",
        "./new_version/pbit_pkg.sv",
        "./new_version/pbit_edge_contrib2.sv",
        "./new_version/majority_vote.sv",
        "./new_version/pbit_prob_compare16.sv",
        "./new_version/pbit_rand16_extract.sv",
        "./new_version/tanh_LUT.sv",
        "./new_version/pbit_8edge_compute.sv",
        "./new_version/edge_prob_compare.sv",
        "./new_version/edge_compare8_named.sv",
        "./new_version/lfsr32_rng32.sv",
        "./new_version/UART_RX.sv",
        "./new_version/UART_TX.sv",
        "./new_version/edge_reg_coupler.sv",
        "./new_version/pbit_node.sv",
        "./new_version/pbit_reg_block.sv",
        "./new_version/pbit_uart_reg_master.sv",
        "./new_version/phase_control_4color.sv",
        "./new_version/pbit_array_kings.sv",
        "./new_version/pbit_uart_reg_subsystem.sv",
        "./new_version/pbit_top.sv",
        "./tb/tb_run_problem.sv",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    parser = argparse.ArgumentParser(description="Generate generic p-bit problem testbench includes.")
    parser.add_argument("--spec", required=True, help="JSON problem spec path")
    parser.add_argument("--out-dir", default="tb/generated", help="Output directory relative to rtl/ when run from rtl/")
    parser.add_argument("--filelist", default="filelist_run_problem.f", help="Output filelist path relative to rtl/")
    args = parser.parse_args()

    spec_path = Path(args.spec).resolve()
    spec = load_json(spec_path)
    problem = problem_from_spec(spec_path, spec)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_data_svh(out_dir / "problem_data.svh", problem)
    write_score_svh(out_dir / "problem_score.svh", problem)
    write_filelist(Path(args.filelist))

    print(f"generated {out_dir / 'problem_data.svh'}")
    print(f"generated {out_dir / 'problem_score.svh'}")
    print(f"generated {args.filelist}")
    print(
        "problem={name} kind={kind} logical={logical} physical={physical} tile_seeds={tile_seeds} "
        "config_edges={config_edges} clear_edges={clear_edges} sweeps={sweeps} runs={runs}".format(
            name=problem["name"],
            kind=problem["kind"],
            logical=problem["num_logical"],
            physical=len(problem["physical_nodes"]),
            tile_seeds=problem["seed_rows"] * problem["seed_cols"],
            config_edges=len(problem["config_edges"]),
            clear_edges=len(problem["clear_edges"]),
            sweeps=problem["num_sweeps"],
            runs=problem["num_runs"],
        )
    )
    print(f"max_neighbors={problem['max_neighbors']} i0_levels={problem['i0_levels']}")


if __name__ == "__main__":
    main()
