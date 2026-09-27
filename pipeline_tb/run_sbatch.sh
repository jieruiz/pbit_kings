#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH -J chi_pipeline_tb
#SBATCH -o chi-pipeline-%j.out
#SBATCH -e chi-pipeline-%j.err
set -eo pipefail
if [[ -z "${SLURM_JOB_ID:-}" ]]; then echo 'Submit with sbatch'; exit 1; fi
set +u
source ~/.bashrc
set -euo pipefail
ROOT="${PROJECT_PATH:-${SLURM_SUBMIT_DIR}}"
TEST="${TEST:-run3x3}"
case "$TEST" in
  rw) TOP=tb; MARKER='^PASS rw_basic:' ;;
  run3x3) TOP=tb_run3x3; MARKER='^\[TB_RUN3X3\] PASS ' ;;
  *) echo "Unknown TEST=$TEST"; exit 1 ;;
esac
WORK="$ROOT/sim_pipeline/${TEST}_${SLURM_JOB_ID}"
"${PYTHON_CMD:-python3}" "$ROOT/pipeline_tb/prepare_tb.py" --source "$ROOT" --dest "$WORK" --test "$TEST"
cd "$WORK/rtl"
echo "Test=$TEST Node=$(hostname) Work=$PWD Start=$(date)"
vcs -full64 -sverilog -timescale=1ns/1ps -f test.f -top "$TOP" -o simv -l compile.log
test -x ./simv
./simv -l sim.log
if grep -Eiq '(^|[^a-z])(fatal|error)(:|\[)' sim.log || ! grep -Eq "$MARKER" sim.log; then
  echo 'FAIL: simulation error or missing PASS marker'; exit 1
fi
echo "PASS: $WORK/rtl/sim.log"
