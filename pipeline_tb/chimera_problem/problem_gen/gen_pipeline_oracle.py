"""Generate cycle-exact Python oracle files for the pipeline Chimera RTL TB."""
import argparse
import csv
import json
import os
import sys
from pathlib import Path

import numpy as np


HERE = Path(__file__).resolve().parent


def default_model_dir():
    configured = os.environ.get("PIPELINE_ORACLE_MODEL_DIR")
    if configured:
        return Path(configured)
    # Local layout: a_P_BIT/{p_bit_chimera,pbit_chimera_pipeline_20260920}
    candidates = []
    for parent in HERE.parents:
        candidates.append(parent / "p_bit_chimera")
        candidates.append(parent.parent / "p_bit_chimera")
    for candidate in candidates:
        if (candidate / "chimera_pbit_hardware_sim_pipeline_20260920.py").exists():
            return candidate
    return HERE.parents[3] / "p_bit_chimera"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_mem(path, values, digits=8):
    mask = (1 << (digits * 4)) - 1
    path.write_text(
        "".join(("{:0" + str(digits) + "x}\n").format(int(value) & mask)
                for value in values),
        encoding="ascii",
    )


def spins_to_hex(spins):
    value = 0
    for index, spin in enumerate(spins):
        if int(spin) > 0:
            value |= 1 << index
    return value


def load_stage_schedule(data_dir):
    manifest = read_json(data_dir / "manifest.json")
    stages = manifest["stages"]
    schedule = np.asarray([float(stage["coefficient"]) for stage in stages],
                          dtype=np.float64)
    durations = np.asarray([int(stage["sweeps"]) for stage in stages],
                           dtype=np.int64)
    if int(np.sum(durations)) != int(manifest["SWEEPS"]):
        raise ValueError("Oracle schedule duration does not match SWEEPS")
    return manifest, schedule, durations


def simulate_oracle(pipeline, problem, manifest, schedule, durations):
    sweeps = int(manifest["SWEEPS"])
    runs = int(manifest["RUNS"])
    majority = int(manifest["MAJORITY"])
    seed_master = int(manifest["SEED_MASTER"])
    init_seed = int(manifest["INIT_SEED"])

    rows = []
    for run in range(runs):
        spins = pipeline.make_initial_spins(init_seed + 7919 * run)
        lfsr_states = pipeline.make_lfsr_states(seed_master + 10 * run)
        best_score = None
        best_spins = None
        for sweep in range(1, sweeps + 1):
            i0 = pipeline.annealing_value(
                sweep - 1,
                sweeps,
                schedule,
                durations=durations,
            )
            for color in (0, 1):
                lfsr_states = pipeline.update_phase(
                    problem,
                    spins,
                    lfsr_states,
                    color,
                    i0,
                    majority,
                    bias_field_convention=pipeline.DEFAULT_BIAS_FIELD_CONVENTION,
                )
            metrics = pipeline.evaluate_state(problem, spins)
            score = int(round(float(metrics["objective"])))
            if best_score is None or score > best_score:
                best_score = score
                best_spins = spins.copy()
            rows.append({
                "run": run,
                "sweep": sweep,
                "cycles": sweep * 2 * (majority + 5),
                "score": score,
                "best": best_score,
                "broken": int(metrics["broken_chains"]),
                "ties": int(metrics["chain_ties"]),
                "i0": int(pipeline.rtl_i0_level(i0)),
                "spins_hex": spins_to_hex(spins),
                "best_spins_hex": spins_to_hex(best_spins),
            })
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default_data = Path(os.environ.get(
        "PIPELINE_ORACLE_DATA_DIR",
        str(HERE.parent / "chimera_pipeline_generated"),
    ))
    parser.add_argument("--data", type=Path, default=default_data)
    parser.add_argument("--model-dir", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    data_dir = args.data.resolve()
    output = (args.output or data_dir).resolve()
    model_dir = (args.model_dir or default_model_dir()).resolve()
    if not model_dir.exists():
        raise SystemExit(
            "Cannot find p_bit_chimera model directory: {}. "
            "Set PYTHON_MODEL_DIR or pass --model-dir.".format(model_dir)
        )
    sys.path.insert(0, str(model_dir))
    import chimera_pbit_hardware_sim_pipeline_20260920 as pipeline

    manifest, schedule, durations = load_stage_schedule(data_dir)
    instance_dir = model_dir / "chimera_3200_benchmarks" / "instances" / manifest["case"]
    problem = pipeline.load_physical_problem(
        instance_dir,
        comparator_mode="edge-le-bias-lt",
        quantization_mode="legacy127",
    )
    rows = simulate_oracle(pipeline, problem, manifest, schedule, durations)

    output.mkdir(parents=True, exist_ok=True)
    write_mem(output / "oracle_score.mem", (row["score"] for row in rows), 8)
    write_mem(output / "oracle_best.mem", (row["best"] for row in rows), 8)
    write_mem(output / "oracle_broken.mem", (row["broken"] for row in rows), 8)
    write_mem(output / "oracle_ties.mem", (row["ties"] for row in rows), 8)
    write_mem(output / "oracle_i0.mem", (row["i0"] for row in rows), 8)
    write_mem(output / "oracle_cycles.mem", (row["cycles"] for row in rows), 16)
    spin_digits = int((int(manifest["N"]) + 3) // 4)
    write_mem(output / "oracle_spins.mem", (row["spins_hex"] for row in rows), spin_digits)
    write_mem(output / "oracle_best_spins.mem",
              (row["best_spins_hex"] for row in rows), spin_digits)
    with (output / "oracle_history.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "model_revision": pipeline.RTL_MODEL_REVISION,
        "case": manifest["case"],
        "runs": int(manifest["RUNS"]),
        "sweeps": int(manifest["SWEEPS"]),
        "majority": int(manifest["MAJORITY"]),
        "rows": len(rows),
        "instance_dir": str(instance_dir),
    }
    (output / "oracle_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n",
        encoding="utf-8",
    )
    print("[PIPELINE_ORACLE] generated rows={} case={} model={}".format(
        len(rows), manifest["case"], pipeline.RTL_MODEL_REVISION
    ))


if __name__ == "__main__":
    main()
