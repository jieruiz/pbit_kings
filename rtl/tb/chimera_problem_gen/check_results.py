"""Independently decode saved physical states and check the SV scores (Python 3.6)."""
import argparse
import csv
from pathlib import Path
from gen_chimera_problem import HERE, load_case, read_json, score


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", default="tb/chimera_generated")
    ap.add_argument("--states", default="chimera_states.txt")
    ap.add_argument("--csv", default="chimera_sweeps.csv")
    args = ap.parse_args()
    manifest = read_json(Path(args.data) / "manifest.json")
    problem, chains, _, _, _, _, target = load_case(manifest["case"])
    with Path(args.csv).open() as f:
        rows = list(csv.DictReader(f))
    states = [dict(field.split("=", 1) for field in line.split())
              for line in Path(args.states).read_text().splitlines() if line.strip()]
    assert len(states) == manifest["RUNS"]
    assert len(rows) == manifest["RUNS"] * manifest["SWEEPS"]
    successes = 0
    for run, record in enumerate(states):
        assert int(record["run"]) == run
        for kind in ("best", "final"):
            bits = int(record[kind + "_spins"], 16)
            decoded = [int(sum(1 if (bits >> p) & 1 else -1 for p in chain) >= 0)
                       for chain in chains]
            actual = score(problem, decoded)
            assert actual == int(record[kind + "_score"]), (run, kind, actual, record)
            if kind == "best":
                assert sum(bit << i for i, bit in enumerate(decoded)) == int(record["best_logical"], 16)
        run_rows = [r for r in rows if int(r["run"]) == run]
        assert [int(r["sweep"]) for r in run_rows] == list(range(1, manifest["SWEEPS"] + 1))
        best = -1
        cycles = 0
        for r in run_rows:
            assert int(r["cycles"]) > cycles
            cycles = int(r["cycles"])
            best = max(best, int(r["score"]))
            assert best == int(r["best"])
        assert best == int(record["best_score"])
        assert int(run_rows[-1]["score"]) == int(record["final_score"])
        first = next((r for r in run_rows if int(r["score"]) >= target), None)
        successes += int(first is not None)
        print("[PY_SCORE_CHECK] run={} best={} target={} first_success={} cycles={}".format(
            run, best, target, first["sweep"] if first else "not_reached", first["cycles"] if first else "NA"))
    print("[PY_SCORE_CHECK] PASS; optimization success {}/{}".format(successes, len(states)))


if __name__ == "__main__":
    main()
