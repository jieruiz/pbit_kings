"""Compare edge<=/bias< Chimera logs with the established <=/<= RTL runs."""
import argparse
import re
from pathlib import Path


REFERENCE = {
    "random_cut_n0096_s401": {
        "target": 354,
        "runs": [(322, 350), (304, 350), (308, 348)],
    },
    "native_cut_n0448_s201": {
        "target": 5847,
        "runs": [(4211, 4287), (4077, 4261), (4033, 4249)],
    },
    "random_sat3_n0024_s401": {
        "target": 96,
        "runs": [(83, 92), (83, 93), (82, 92)],
    },
}

HEADER_RE = re.compile(
    r"\[CHIMERA\] case=(\S+).* runs=(\d+) sweeps=(\d+) majority=(\d+)")
RUN_RE = re.compile(
    r"\[CHIMERA_RUN\] run=(\d+) final=(-?\d+) best=(-?\d+) target=(-?\d+)")


def candidate_files(paths):
    files = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            files.extend(path.rglob("*.out"))
            files.extend(path.rglob("sim_chimera.log"))
        elif path.is_file():
            files.append(path)
        else:
            raise ValueError("Path does not exist: {}".format(path))
    return sorted(set(files))


def parse_log(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    header = HEADER_RE.search(text)
    if not header or header.group(1) not in REFERENCE:
        return None
    case_name = header.group(1)
    runs = {}
    for match in RUN_RE.finditer(text):
        runs[int(match.group(1))] = {
            "final": int(match.group(2)),
            "best": int(match.group(3)),
            "target": int(match.group(4)),
        }
    return {
        "path": path,
        "case": case_name,
        "run_count": int(header.group(2)),
        "sweeps": int(header.group(3)),
        "majority": int(header.group(4)),
        "runs": runs,
        "tb_pass": "[TB_CHIMERA_PROBLEM] PASS" in text,
        "python_pass": "[PY_SCORE_CHECK] PASS" in text,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="Candidate .out/log files or directories")
    args = parser.parse_args()

    parsed = [result for result in
              (parse_log(path) for path in candidate_files(args.paths)) if result]
    by_case = {}
    for result in parsed:
        current = by_case.get(result["case"])
        if current is None or result["path"].stat().st_mtime > current["path"].stat().st_mtime:
            by_case[result["case"]] = result

    errors = []
    print("case,run,old_final,new_final,delta_final,old_best,new_best,delta_best,target")
    for case_name in REFERENCE:
        result = by_case.get(case_name)
        if result is None:
            errors.append("Missing candidate log for {}".format(case_name))
            continue
        if (result["run_count"], result["sweeps"], result["majority"]) != (3, 500, 5):
            errors.append("{} parameters are runs={} sweeps={} majority={}, expected 3/500/5".format(
                case_name, result["run_count"], result["sweeps"], result["majority"]))
        if not result["tb_pass"] or not result["python_pass"]:
            errors.append("{} missing TB or Python PASS marker".format(case_name))
        for run_index, (old_final, old_best) in enumerate(REFERENCE[case_name]["runs"]):
            new = result["runs"].get(run_index)
            if new is None:
                errors.append("{} missing run {}".format(case_name, run_index))
                continue
            target = REFERENCE[case_name]["target"]
            if new["target"] != target:
                errors.append("{} target changed from {} to {}".format(
                    case_name, target, new["target"]))
            print("{},{},{},{},{:+d},{},{},{:+d},{}".format(
                case_name, run_index, old_final, new["final"], new["final"] - old_final,
                old_best, new["best"], new["best"] - old_best, target))

    if errors:
        for message in errors:
            print("ERROR: {}".format(message))
        raise SystemExit(1)
    print("[EDGE_LE_BIAS_LT_COMPARE] PASS structural and independent-score checks")
    print("Score deltas are informational; stochastic trajectories are expected to change.")


if __name__ == "__main__":
    main()
