#!/usr/bin/env python3
import argparse
import json
import random
from pathlib import Path


NUM_LOGICAL = 50
EDGE_RANDOM_MAX_CODE = 127
RTL_I0_LEVEL_MAX = 63


def load_weight_matrix(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                rows.append([float(x) for x in line.split()])

    if len(rows) != NUM_LOGICAL or any(len(row) != NUM_LOGICAL for row in rows):
        raise ValueError(f"W must be {NUM_LOGICAL}x{NUM_LOGICAL}")

    for i in range(NUM_LOGICAL):
        rows[i][i] = 0.0
        for j in range(NUM_LOGICAL):
            if abs(rows[i][j] - rows[j][i]) > 1e-9:
                raise ValueError("W must be symmetric")

    return rows


def load_mapping(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    mapping = {int(k): [int(q) for q in v] for k, v in raw.items()}
    missing = set(range(NUM_LOGICAL)) - set(mapping)
    if missing:
        raise ValueError(f"Mapping file missing logical nodes: {sorted(missing)}")

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
    raise ValueError(f"Not a king-neighbor edge: ({r1},{c1})-({r2},{c2})")


def build_physical_problem(W, mapping, kings_cols):
    max_w = max(W[i][j] for i in range(NUM_LOGICAL) for j in range(NUM_LOGICAL))
    if max_w <= 0:
        raise ValueError("All weights are zero")

    physical_nodes = sorted({q for chain in mapping.values() for q in chain})
    phys_to_idx = {q: idx for idx, q in enumerate(physical_nodes)}
    n_phys = len(physical_nodes)

    prob = [[0 for _ in range(n_phys)] for _ in range(n_phys)]
    sign = [[0 for _ in range(n_phys)] for _ in range(n_phys)]

    for a in range(NUM_LOGICAL):
        for b in range(a + 1, NUM_LOGICAL):
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

            p_each_code = quantize_to_int(p_edge / len(couplers), 7)
            for qa, qb in couplers:
                ia = phys_to_idx[qa]
                ib = phys_to_idx[qb]
                prob[ia][ib] = max(prob[ia][ib], p_each_code)
                prob[ib][ia] = prob[ia][ib]
                sign[ia][ib] = 1
                sign[ib][ia] = 1

    for chain in mapping.values():
        for i in range(len(chain)):
            for j in range(i + 1, len(chain)):
                qa = chain[i]
                qb = chain[j]
                if are_kings_neighbors(qa, qb, kings_cols):
                    ia = phys_to_idx[qa]
                    ib = phys_to_idx[qb]
                    prob[ia][ib] = EDGE_RANDOM_MAX_CODE
                    prob[ib][ia] = EDGE_RANDOM_MAX_CODE
                    sign[ia][ib] = -1
                    sign[ib][ia] = -1

    return physical_nodes, phys_to_idx, prob, sign


def make_seed(seed_rng):
    seed = seed_rng.randrange(1, 2**32)
    return seed if seed else 1


def build_node_seeds(physical_nodes, kings_cols, seed_master):
    max_row = max(kings_coord(q, kings_cols)[0] for q in physical_nodes)
    tile_rows = (max(kings_cols, max_row + 1) + 1) // 2
    tile_cols = (kings_cols + 1) // 2
    tile_rng = random.Random(seed_master)
    tile_seeds = [make_seed(tile_rng) for _ in range(tile_rows * tile_cols)]
    init_rng = random.Random(seed_master ^ 0x5A17_1234)

    seeds = []
    init_spins = []
    for q in physical_nodes:
        row, col = kings_coord(q, kings_cols)
        tile_id = (row // 2) * tile_cols + (col // 2)
        seed = (tile_seeds[tile_id] ^ ((q + 1) * 0x9E3779B9)) & 0xFFFFFFFF
        seeds.append(seed if seed else 1)
        init_spins.append(init_rng.randrange(0, 2))

    return seeds, init_spins, tile_rows, tile_cols, len(tile_seeds)


def build_clear_edges(kings_rows, kings_cols):
    edges = []
    for r in range(kings_rows):
        for c in range(kings_cols - 1):
            edges.append(("EDGE_TYPE_EDGE_H", r, c))
    for r in range(kings_rows - 1):
        for c in range(kings_cols):
            edges.append(("EDGE_TYPE_EDGE_V", r, c))
    for r in range(kings_rows - 1):
        for c in range(kings_cols - 1):
            edges.append(("EDGE_TYPE_EDGE_DSE", r, c))
    for r in range(kings_rows - 1):
        for c in range(1, kings_cols):
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
            rtl_sign = 0 if sign[ia][ib] > 0 else 1
            edges.append((edge_type, row, col, rtl_prob, rtl_sign))
    return edges


def build_logical_edges(W):
    edges = []
    for i in range(NUM_LOGICAL):
        for j in range(i + 1, NUM_LOGICAL):
            weight = int(round(W[i][j]))
            if weight > 0:
                edges.append((i, j, weight))
    return edges


def sv_arr_assign(name, values, fmt):
    lines = []
    for idx, value in enumerate(values):
        lines.append(f"        {name}[{idx}] = {fmt(value)};")
    return lines


def python_like_schedule(num_sweeps, num_i0_levels):
    counts = [0 for _ in range(num_i0_levels)]
    for sweep in range(num_sweeps):
        level = round((num_i0_levels - 1) * sweep / max(1, num_sweeps - 1))
        counts[level] += 1
    return counts


def build_i0_levels(i0_start, i0_end, num_i0_levels):
    if i0_end <= 0:
        raise ValueError("i0_end must be positive")
    if i0_start < 0:
        raise ValueError("i0_start must be non-negative")

    levels = []
    for idx in range(num_i0_levels):
        alpha = idx / max(1, num_i0_levels - 1)
        i0 = i0_start + (i0_end - i0_start) * alpha
        level = int(round(i0 * RTL_I0_LEVEL_MAX / i0_end))
        levels.append(max(0, min(RTL_I0_LEVEL_MAX, level)))
    return levels


def write_svh(path, args, W, mapping, physical_nodes, phys_to_idx, config_edges, clear_edges, node_seeds, init_spins, logical_edges, tile_info):
    chain_entries = []
    chain_start = [0]
    for logical in range(NUM_LOGICAL):
        chain_entries.extend(phys_to_idx[q] for q in mapping[logical])
        chain_start.append(len(chain_entries))

    rows = []
    cols = []
    phys_qs = []
    for q in physical_nodes:
        r, c = kings_coord(q, args.kings_cols)
        rows.append(r)
        cols.append(c)
        phys_qs.append(q)

    i0_levels = build_i0_levels(args.i0_start, args.i0_end, args.num_i0_levels)
    if args.num_sweeps is None:
        intervals = [args.interval_per_level for _ in i0_levels]
    else:
        intervals = python_like_schedule(args.num_sweeps, len(i0_levels))
    num_sweeps = sum(intervals)

    lines = []
    lines.append("`ifndef TB_W50_MAXCUT_DATA_SVH")
    lines.append("`define TB_W50_MAXCUT_DATA_SVH")
    lines.append("// Generated by tb/gen_w50_maxcut_data.py. Re-run the generator when W or mapping changes.")
    lines.append(f"localparam int unsigned W50_NUM_LOGICAL = {NUM_LOGICAL};")
    lines.append(f"localparam int unsigned W50_NUM_PHYSICAL = {len(physical_nodes)};")
    lines.append(f"localparam int unsigned W50_NUM_CONFIG_EDGES = {len(config_edges)};")
    lines.append(f"localparam int unsigned W50_NUM_CLEAR_EDGES = {len(clear_edges)};")
    lines.append(f"localparam int unsigned W50_NUM_CHAIN_ENTRIES = {len(chain_entries)};")
    lines.append(f"localparam int unsigned W50_NUM_LOGICAL_EDGES = {len(logical_edges)};")
    lines.append(f"localparam int unsigned W50_TOTAL_LOGICAL_WEIGHT = {sum(weight for _, _, weight in logical_edges)};")
    lines.append(f"localparam int unsigned W50_NUM_I0_LEVELS = {len(i0_levels)};")
    lines.append(f"localparam int unsigned W50_NUM_SWEEPS = {num_sweeps};")
    lines.append(f"localparam int unsigned W50_NUM_MAJORITY = {args.num_majority};")
    lines.append(f"localparam int unsigned W50_MIN_PASS_CUT = {args.min_cut};")
    lines.append(f"localparam int unsigned W50_KINGS_ROWS = {args.kings_rows};")
    lines.append(f"localparam int unsigned W50_KINGS_COLS = {args.kings_cols};")
    lines.append(f"localparam int unsigned W50_TILE_ROWS = {tile_info[0]};")
    lines.append(f"localparam int unsigned W50_TILE_COLS = {tile_info[1]};")
    lines.append(f"localparam int unsigned W50_NUM_TILE_LFSRS = {tile_info[2]};")
    lines.append("")
    lines.append("logic [5:0] w50_phys_row [W50_NUM_PHYSICAL];")
    lines.append("logic [5:0] w50_phys_col [W50_NUM_PHYSICAL];")
    lines.append("logic [31:0] w50_phys_q [W50_NUM_PHYSICAL];")
    lines.append("logic [31:0] w50_node_seed [W50_NUM_PHYSICAL];")
    lines.append("logic w50_node_init_spin [W50_NUM_PHYSICAL];")
    lines.append("logic [EDGE_TYPE_WIDTH-1:0] w50_edge_type [W50_NUM_CONFIG_EDGES];")
    lines.append("logic [5:0] w50_edge_row [W50_NUM_CONFIG_EDGES];")
    lines.append("logic [5:0] w50_edge_col [W50_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] w50_edge_prob [W50_NUM_CONFIG_EDGES];")
    lines.append("logic w50_edge_sign [W50_NUM_CONFIG_EDGES];")
    lines.append("logic [EDGE_TYPE_WIDTH-1:0] w50_clear_edge_type [W50_NUM_CLEAR_EDGES];")
    lines.append("logic [5:0] w50_clear_edge_row [W50_NUM_CLEAR_EDGES];")
    lines.append("logic [5:0] w50_clear_edge_col [W50_NUM_CLEAR_EDGES];")
    lines.append("int unsigned w50_chain_start [W50_NUM_LOGICAL + 1];")
    lines.append("int unsigned w50_chain_phys_idx [W50_NUM_CHAIN_ENTRIES];")
    lines.append("int unsigned w50_logical_edge_a [W50_NUM_LOGICAL_EDGES];")
    lines.append("int unsigned w50_logical_edge_b [W50_NUM_LOGICAL_EDGES];")
    lines.append("int unsigned w50_logical_edge_weight [W50_NUM_LOGICAL_EDGES];")
    lines.append("logic [I0_LEVEL_WIDTH-1:0] w50_i0_level [W50_NUM_I0_LEVELS];")
    lines.append("logic [SWEEP_INTERVAL_WIDTH-1:0] w50_sweep_interval [W50_NUM_I0_LEVELS];")
    lines.append("")
    lines.append("task automatic load_w50_maxcut_data();")
    lines.append("    begin")
    lines.extend(sv_arr_assign("w50_phys_row", rows, lambda v: f"6'd{v}"))
    lines.extend(sv_arr_assign("w50_phys_col", cols, lambda v: f"6'd{v}"))
    lines.extend(sv_arr_assign("w50_phys_q", phys_qs, lambda v: f"32'd{v}"))
    lines.extend(sv_arr_assign("w50_node_seed", node_seeds, lambda v: f"32'h{v:08x}"))
    lines.extend(sv_arr_assign("w50_node_init_spin", init_spins, lambda v: f"1'b{v}"))
    for idx, (edge_type, row, col, prob_code, rtl_sign) in enumerate(config_edges):
        lines.append(f"        w50_edge_type[{idx}] = {edge_type};")
        lines.append(f"        w50_edge_row[{idx}] = 6'd{row};")
        lines.append(f"        w50_edge_col[{idx}] = 6'd{col};")
        lines.append(f"        w50_edge_prob[{idx}] = 7'd{prob_code};")
        lines.append(f"        w50_edge_sign[{idx}] = 1'b{rtl_sign};")
    for idx, (edge_type, row, col) in enumerate(clear_edges):
        lines.append(f"        w50_clear_edge_type[{idx}] = {edge_type};")
        lines.append(f"        w50_clear_edge_row[{idx}] = 6'd{row};")
        lines.append(f"        w50_clear_edge_col[{idx}] = 6'd{col};")
    lines.extend(sv_arr_assign("w50_chain_start", chain_start, lambda v: f"{v}"))
    lines.extend(sv_arr_assign("w50_chain_phys_idx", chain_entries, lambda v: f"{v}"))
    for idx, (a, b, weight) in enumerate(logical_edges):
        lines.append(f"        w50_logical_edge_a[{idx}] = {a};")
        lines.append(f"        w50_logical_edge_b[{idx}] = {b};")
        lines.append(f"        w50_logical_edge_weight[{idx}] = {weight};")
    lines.extend(sv_arr_assign("w50_i0_level", i0_levels, lambda v: f"6'd{v}"))
    lines.extend(sv_arr_assign("w50_sweep_interval", intervals, lambda v: f"16'd{v}"))
    lines.append("    end")
    lines.append("endtask")
    lines.append("`endif")
    lines.append("")

    path.write_text("\n".join(lines), encoding="ascii")


def main():
    parser = argparse.ArgumentParser(description="Generate SV data for the W50 king-graph MaxCut UART testbench.")
    parser.add_argument("--w-path", default="/home/Hongjie_Zeng/python/p_bit_pipeline/generated_W50.txt")
    parser.add_argument("--mapping-path", default="/home/Hongjie_Zeng/python/p_bit_pipeline/KingsGraph_Embedding_W50_Best_19x19.json")
    parser.add_argument("--out", default="tb/tb_w50_maxcut_data.svh")
    parser.add_argument("--kings-cols", type=int, default=19)
    parser.add_argument("--kings-rows", type=int, default=20)
    parser.add_argument("--seed-master", type=int, default=2461)
    parser.add_argument("--num-majority", type=int, default=5)
    parser.add_argument("--num-sweeps", type=int, default=None)
    parser.add_argument("--num-i0-levels", type=int, default=16)
    parser.add_argument("--i0-start", type=float, default=0.5)
    parser.add_argument("--i0-end", type=float, default=6.0)
    parser.add_argument("--interval-per-level", type=int, default=2)
    parser.add_argument("--min-cut", type=int, default=450)
    args = parser.parse_args()

    if args.num_i0_levels < 1 or args.num_i0_levels > 64:
        raise ValueError("--num-i0-levels must be in [1, 64]")
    if args.num_i0_levels % 4 != 0:
        raise ValueError("--num-i0-levels must be a multiple of 4 for the current TB packer")
    if args.num_sweeps is not None and args.num_sweeps < args.num_i0_levels:
        raise ValueError("--num-sweeps must be >= --num-i0-levels")

    W = load_weight_matrix(args.w_path)
    mapping = load_mapping(args.mapping_path)
    physical_nodes, phys_to_idx, prob, sign = build_physical_problem(W, mapping, args.kings_cols)
    config_edges = build_config_edges(physical_nodes, prob, sign, args.kings_cols)
    clear_edges = build_clear_edges(args.kings_rows, args.kings_cols + 1)
    node_seeds, init_spins, tile_rows, tile_cols, num_tile_lfsrs = build_node_seeds(
        physical_nodes,
        args.kings_cols,
        args.seed_master,
    )
    logical_edges = build_logical_edges(W)

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
        W,
        mapping,
        physical_nodes,
        phys_to_idx,
        config_edges,
        clear_edges,
        node_seeds,
        init_spins,
        logical_edges,
        (tile_rows, tile_cols, num_tile_lfsrs),
    )

    total_weight = sum(weight for _, _, weight in logical_edges)
    print(f"generated {out}")
    print(f"physical_nodes={len(physical_nodes)} config_edges={len(config_edges)} clear_edges={len(clear_edges)}")
    print(f"logical_edges={len(logical_edges)} total_logical_weight={total_weight} max_neighbors={max_neighbors}")
    generated_sweeps = args.num_sweeps if args.num_sweeps is not None else args.num_i0_levels * args.interval_per_level
    print(f"num_sweeps={generated_sweeps} num_majority={args.num_majority} min_cut={args.min_cut}")
    print(f"i0_start={args.i0_start} i0_end={args.i0_end} num_i0_levels={args.num_i0_levels}")


if __name__ == "__main__":
    main()
