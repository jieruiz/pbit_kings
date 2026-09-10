"""Generate real register transactions and independent scoring data (Python 3.6+)."""
import argparse
import csv
import hashlib
import json
import math
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASES = (
    "random_cut_n0096_s401", "dense_cut_n0024_s101",
    "random3_cut_n0096_s901", "native_cut_n0448_s201",
    "random_sat3_n0024_s401", "uniform_sat3_n0060_s501",
    "random_sat4_n0012_s401",
)
ROWS = COLS = 20
N = ROWS * COLS * 8


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def edge_address(a, b):
    """One owner per undirected edge: (unit row, col, type, track)."""
    if a > b:
        a, b = b, a
    if not 0 <= a < b < N:
        raise ValueError("Bad physical endpoints: {} {}".format(a, b))
    ra, ca = divmod(a // 8, COLS)
    rb, cb = divmod(b // 8, COLS)
    ua, ka = divmod(a % 8, 4)
    ub, kb = divmod(b % 8, 4)
    if (ra, ca) == (rb, cb) and ua == 0 and ub == 1:
        return ra, ca, ka, kb
    if ua == ub == 1 and ka == kb and ra == rb and cb == ca + 1:
        return ra, ca, 4, ka
    if ua == ub == 0 and ka == kb and ca == cb and rb == ra + 1:
        return ra, ca, 5, ka
    raise ValueError("Not a Chimera edge: {} {}".format(a, b))


def all_edges():
    for r in range(ROWS):
        for c in range(COLS):
            base = (r * COLS + c) * 8
            for left in range(4):
                for right in range(4):
                    yield base + left, base + 4 + right
            for k in range(4):
                if c + 1 < COLS:
                    yield base + 4 + k, base + 12 + k
                if r + 1 < ROWS:
                    yield base + k, base + COLS * 8 + k


def lfsr_step(state):
    feedback = ((state >> 31) ^ (state >> 21) ^ (state >> 1) ^ state) & 1
    return ((state << 1) | feedback) & 0xffffffff


def initial_state(run, master=2461, init=314592):
    rng = random.Random(master + 10 * run)
    seeds = set()
    while len(seeds) < N // 2:
        seeds.add(rng.randrange(1, 1 << 32))
    state = (init + 7919 * run) & 0xffffffff or 1
    spins = []
    for _ in range(N):
        state = lfsr_step(state)
        spins.append(state & 1)
    return sorted(seeds), spins


def score(problem, bits):
    if problem["type"] == "maxcut":
        return sum(w for a, b, w in problem["edges"] if bits[a] != bits[b])
    return sum(any(bool(bits[abs(lit) - 1]) == (lit > 0) for lit in clause)
               for clause in problem["clauses"])


def load_case(name):
    root = HERE / "inputs" / name
    p = read_json(root / "problem.json")
    physical = read_json(root / "physical_ising.json")
    embedding = read_json(root / "embedding.json")["chains"]
    cert = read_json(root / "certificate.json")
    if physical["n"] != N or p["type"] not in ("maxcut", "sat"):
        raise ValueError("Only the supplied C20 MaxCut/SAT embeddings are supported")
    chains = [embedding[str(i)] for i in range(len(embedding))]
    used = [v for chain in chains for v in chain]
    if len(chains) < p["n"] or not all(chains) or len(set(used)) != len(used):
        raise ValueError("Missing/overlapping embedding chains")
    if not all(0 <= v < N for v in used):
        raise ValueError("Embedding exceeds physical array")
    h = [0] * N
    for v, value in physical["h"]:
        if v not in used or h[v] != 0:
            raise ValueError("Bad/duplicate bias endpoint")
        h[v] = value
    couplings = {}
    for a, b, value in physical["J"]:
        key = tuple(sorted((a, b)))
        edge_address(*key)
        if key in couplings or a not in used or b not in used:
            raise ValueError("Duplicate edge or edge outside embedding")
        couplings[key] = value
    # Check each chain is connected by physical couplings, not just valid IDs.
    adjacency = {v: set() for v in used}
    for a, b in couplings:
        adjacency[a].add(b)
        adjacency[b].add(a)
    for chain in chains:
        remaining = set(chain)
        frontier = [remaining.pop()]
        while frontier:
            reached = adjacency[frontier.pop()] & remaining
            remaining -= reached
            frontier.extend(reached)
        if remaining:
            raise ValueError("Disconnected chain")
    target = cert["optimum"] if p["type"] == "maxcut" else cert["maximum_satisfied"]
    if score(p, cert["assignment"]) != target:
        raise ValueError("Certificate assignment does not attain its objective")
    values = h + list(couplings.values())
    scale = max([1.0] + [abs(x) for x in values])
    # Same global scaling and ties-to-even rounding as numpy.rint in the model.
    quantize = lambda value: int(round(abs(value) / scale * 127))
    return p, chains, h, couplings, scale, quantize, target


def schedule(args):
    if not all(math.isfinite(x) and x >= 0 for x in (args.i0_start, args.i0_end)):
        raise ValueError("I0 coefficients must be finite and nonnegative")
    with (HERE / "inputs" / "anneal_i0_32_dec.txt").open(encoding="utf-8") as f:
        table = list(csv.DictReader(f))
    if [int(row["level"]) for row in table] != list(range(32)):
        raise ValueError("Bad 32-level table")
    levels = [float(row["I0"]) for row in table]
    requested = [args.i0_start + (args.i0_end - args.i0_start) * i / 31 for i in range(32)]
    if args.schedule == "fixed":
        requested = [args.i0_start] * 32
    ids = (list(range(32)) if args.schedule == "table" else
           [min(range(32), key=lambda i: abs(levels[i] - v)) for v in requested])
    # Match the Python model's nearest-stage placement, including half endpoints.
    per_sweep = [ids[round(31 * s / max(1, args.sweeps - 1))] for s in range(args.sweeps)]
    stages = []
    for level in per_sweep:
        if stages and stages[-1][0] == level and stages[-1][1] < 65536:
            stages[-1][1] += 1
        else:
            stages.append([level, 1])
    if len(stages) > 32:
        raise ValueError("Schedule needs more than 32 hardware stages")
    return table, stages, per_sweep


def write_mem(path, values, digits=8):
    mask = (1 << (digits * 4)) - 1
    path.write_text("".join(("{:0" + str(digits) + "x}\n").format(int(v) & mask)
                            for v in (values or [0])), encoding="ascii")


def generate(args):
    if not 1 <= args.sweeps <= (1 << 24) or not 1 <= args.majority <= 32 or args.runs < 1:
        raise ValueError("Invalid actual sweep/majority/run count")
    p, chains, h, couplings, scale, quantize, target = load_case(args.case)
    table, stages, per_sweep = schedule(args)
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    chain_start, chain_nodes = [0], []
    for chain in chains:
        chain_nodes.extend(chain)
        chain_start.append(len(chain_nodes))
    graph = p.get("edges", [])
    clause_start, literals = [0], []
    for clause in p.get("clauses", []):
        literals.extend(clause)
        clause_start.append(len(literals))
    for name, values in (("chain_start", chain_start), ("chain_nodes", chain_nodes),
                         ("graph_a", [x[0] for x in graph]), ("graph_b", [x[1] for x in graph]),
                         ("graph_w", [x[2] for x in graph]), ("clause_start", clause_start),
                         ("literals", literals), ("sweep_i0", per_sweep)):
        if any(int(v) != v or not -(1 << 31) <= v < (1 << 31) for v in values):
            raise ValueError("Scoring data exceeds signed 32-bit range")
        write_mem(out / (name + ".mem"), values)
    counts = []
    padded_stages = stages + [[0, 1]] * (32 - len(stages))
    for run in range(args.runs):
        seeds, spins = initial_state(run, args.seed_master, args.init_seed)
        write_mem(out / ("initial_{}.mem".format(run)), spins, 1)
        program = []

        def tx(op, addr, value):
            program.append((op << 48) | (addr << 32) | (value & 0xffffffff))

        def wr(addr, value):
            tx(1, addr, value)

        def check(addr, value):
            tx(2, addr, value)

        cfg = (args.sweeps - 1) | ((args.majority - 1) << 24)
        wr(4, cfg)
        check(4, cfg)
        for i in range(8):
            value = sum(padded_stages[4 * i + k][0] << (8 * k) for k in range(4))
            wr(0x14 + 4 * i, value)
            check(0x14 + 4 * i, value)
        for i in range(16):
            value = (padded_stages[2 * i][1] - 1) | ((padded_stages[2 * i + 1][1] - 1) << 16)
            wr(0x34 + 4 * i, value)
            check(0x34 + 4 * i, value)
        edge_cfg = {}
        for a, b in all_edges():
            value = couplings.get((a, b), 0)
            prob = quantize(value)
            # RTL sign=1 adds the neighbor; physical energy has +J*s_i*s_j.
            # Consequently the MAC must implement -J and -h, NOT +J and +h.
            edge_cfg[edge_address(a, b)] = (int(prob != 0) | (int(value < 0) << 1) | (prob << 2))
        for r in range(ROWS):
            for c in range(COLS):
                unit = r * COLS + c
                wr(0x74, r | (c << 8))
                check(0x74, r | (c << 8))
                for node in range(8):
                    v = unit * 8 + node
                    prob, sign = quantize(h[v]), int(h[v] < 0)
                    wr(0x78, (node % 4) | ((node // 4) << 8))
                    wr(0x7c, 7 | (spins[v] << 8) | (sign << 11) | (prob << 12))
                    wr(0x80, 3)  # APPLY + READBACK; no row/array broadcast.
                    check(0x84, spins[v] | (sign << 3) | (prob << 4))
                for k in range(4):
                    wr(0x88, k)
                    wr(0x8c, seeds[unit * 4 + k])
                    wr(0x90, 3)
                    check(0x94, seeds[unit * 4 + k])
                for kind in range(6):
                    for k in range(4):
                        key = (r, c, kind, k)
                        if key not in edge_cfg:
                            continue  # No external edge beyond the array boundary.
                        wr(0x98, kind | (k << 8))
                        wr(0x9c, edge_cfg[key])
                        wr(0xa0, 5)  # APPLY + READBACK, including every disabled edge.
                        check(0xa4, edge_cfg[key])
        check(0x0c, 0)
        write_mem(out / ("config_{}.mem".format(run)), program, 14)
        counts.append(len(program))
    if len(set(counts)) != 1:
        raise ValueError("Run program sizes differ")
    params = {"ROWS": ROWS, "COLS": COLS, "N": N, "CHAINS": len(chains),
              "CHAIN_NODES": len(chain_nodes), "VARIABLES": p["n"],
              "EDGES": len(graph), "CLAUSES": len(p.get("clauses", [])),
              "LITERALS": len(literals), "SAT": int(p["type"] == "sat"),
              "TARGET": target, "SWEEPS": args.sweeps, "RUNS": args.runs,
              "MAJORITY": args.majority, "COMMANDS": counts[0],
              "SEED_MASTER": args.seed_master, "INIT_SEED": args.init_seed}
    header = ['// Generated by gen_chimera_problem.py; do not edit.',
              'localparam P_CASE = "{}";'.format(args.case)]
    header += ["localparam integer P_{} = {};".format(k, v) for k, v in params.items()]
    (out / "problem.svh").write_text("\n".join(header) + "\n", encoding="ascii")
    inputs = HERE / "inputs" / args.case
    hashes = {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(inputs.glob("*.json"))}
    hashes["../anneal_i0_32_dec.txt"] = hashlib.sha256((HERE / "inputs" / "anneal_i0_32_dec.txt").read_bytes()).hexdigest()
    manifest = dict(params, case=args.case, source_sha256=hashes, quantization_scale=scale,
                    physical_edges=len(couplings), all_hardware_edges=len(list(all_edges())),
                    zeroed_nonzero_coefficients=sum(quantize(v) == 0 for v in h + list(couplings.values()) if v),
                    stages=[dict(i0_id=i, coefficient=float(table[i]["I0"]), sweeps=n) for i, n in stages],
                    transport="register bus by default; +UART enables serial transport",
                    sign_convention="MAC=-J*s-h; RTL sign bit one means positive contribution",
                    initial_state="Full 3200 spins and 1600 sorted unique seeds, matching Python source algorithm",
                    bias_placement="source, no redistribution or replication")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("[GEN_CHIMERA] case={} logical={} physical_used={} J={} all_edges={} target={} scale={}".format(
        args.case, len(chains), len(chain_nodes), len(couplings), len(list(all_edges())), target, scale))
    print("[GEN_CHIMERA] runs={} sweeps={} majority={} stages={}".format(args.runs, args.sweeps, args.majority, stages))
    print("generated {}".format(out))
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES, default=CASES[0])
    parser.add_argument("--output", default=str(HERE.parent / "chimera_generated"))
    parser.add_argument("--sweeps", type=int, default=200)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--majority", type=int, default=5)
    parser.add_argument("--seed-master", type=int, default=2461)
    parser.add_argument("--init-seed", type=int, default=314592)
    parser.add_argument("--schedule", choices=("linear", "table", "fixed"), default="linear")
    parser.add_argument("--i0-start", type=float, default=0.1)
    parser.add_argument("--i0-end", type=float, default=4.0)
    generate(parser.parse_args())


if __name__ == "__main__":
    main()
