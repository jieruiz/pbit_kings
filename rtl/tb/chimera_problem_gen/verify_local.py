"""Optional local Vivado Simulator regression. Never changes production RTL."""
import argparse
import subprocess
import sys
import time
from pathlib import Path
from gen_chimera_problem import HERE, CASES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado-bin", default="C:/Xilinx/vivado/Vivado/2018.3/bin")
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    parser.add_argument("--sweeps", type=int, default=32)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--majority", type=int, default=5)
    parser.add_argument("--uart-smoke", action="store_true")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    rtl = HERE.parents[1]
    root = Path(args.output).resolve()
    root.mkdir(parents=True, exist_ok=True)
    files = [str(rtl / line.strip()) for line in (rtl / "filelist_pbit_top_chimera.f").read_text().splitlines()
             if line.strip() and not line.startswith("-")]
    files += [str(rtl / "tb/chimera_problem_harness.sv"), str(rtl / "tb/tb_run_chimera_problem.sv")]
    for case in args.cases:
        work = root / case
        work.mkdir(exist_ok=False)
        def run(command, log):
            with (work / log).open("w") as f:
                result = subprocess.run(command, cwd=str(work), stdout=f, stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError("Failed: {} (see {})".format(command[0], work / log))
        data = work / "tb/chimera_generated"
        print("VERIFY {}".format(case), flush=True)
        run([sys.executable, str(HERE / "gen_chimera_problem.py"), "--case", case,
             "--runs", str(args.runs), "--sweeps", str(args.sweeps), "--majority", str(args.majority),
             "--output", str(data)], "generate.log")
        run([str(Path(args.vivado_bin) / "xvlog.bat"), "--sv", "-i", str(data)] + files, "analyze.log")
        run([str(Path(args.vivado_bin) / "xelab.bat"), "--relax", "--timescale", "1ns/1ps",
             "--mt", "4", "work.tb_chimera_problem", "-s", "problem"], "elaborate.log")
        run([str(Path(args.vivado_bin) / "xsim.bat"), "problem", "-runall", "-maxdeltaid", "10000", "-log", "simulation.log", "-testplusarg", "TRACE_CONFIG"] +
            (["-testplusarg", "UART_SMOKE"] if args.uart_smoke else []), "run.log")
        log = (work / "simulation.log").read_text(errors="replace")
        if "[TB_CHIMERA_PROBLEM] PASS" not in log or "Fatal:" in log or "WARNING:" in log:
            raise RuntimeError("Simulation not clean: {}".format(work / "simulation.log"))
        run([sys.executable, str(HERE / "check_results.py")], "score_check.log")
        print("PASS {}".format(case), flush=True)


if __name__ == "__main__":
    main()
