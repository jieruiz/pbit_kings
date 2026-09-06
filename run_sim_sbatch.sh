#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH -J pbit_pll_cfg_sim
#SBATCH -o pbit-sim-%j.out
#SBATCH -e pbit-sim-%j.err
set -eo pipefail
set +u
source ~/.bashrc
set -u
export PROJECT_PATH="${PROJECT_PATH:-${SLURM_SUBMIT_DIR:-$PWD}}"
TEST="${TEST:-pll_uart}"
case "$TEST" in
  pll_regs) LIST=filelist_pll_cfg_regs.f; TOP=tb_pll_cfg_regs ;;
  pll_uart) LIST=filelist_pll_cfg_uart.f; TOP=tb_pll_cfg_uart ;;
  pll_wrapper) LIST=filelist_pll_wrapper.f; TOP=tb_pll_wrapper ;;
  rw) LIST=filelist_rw_basic.f; TOP=tb ;;
  3x3) LIST=filelist_run_3x3.f; TOP=tb ;;
  majority) LIST=filelist_run_3x3_majority.f; TOP=tb ;;
  maxcut3x3) LIST=filelist_run_3x3_maxcut.f; TOP=tb ;;
  w50) LIST=filelist_run_w50_maxcut.f; TOP=tb ;;
  ksat) LIST=filelist_run_ksat_10v40c.f; TOP=tb ;;
  problem) LIST=filelist_run_problem.f; TOP=tb ;;
  *) echo "Unknown TEST=$TEST" >&2; exit 2 ;;
esac
test -r "$PROJECT_PATH/rtl/new_version/pbit_pkg.sv"
JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$PROJECT_PATH/sim_runs/${TEST}_${JOB}"
mkdir -p "$WORK"
# Each job owns both generated includes and all VCS artifacts. Never clean a shared csrc.
cp -a "$PROJECT_PATH/rtl" "$WORK/rtl"
cd "$WORK/rtl"
echo "Node: $(hostname) Test: $TEST Start: $(date) Work: $PWD"
if [ "$TEST" = problem ]; then
  SPEC="${SPEC:-tb/problem_gen/specs/w50_maxcut.json}"
  python3 --version
  KIND=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kind"])' "$SPEC")
  case "$KIND" in
    native_king_maxcut) GENERATOR=gen_native_king_maxcut.py ;;
    tsp5_full_kings40) GENERATOR=gen_tsp5_full_kings40.py ;;
    *) GENERATOR=gen_problem.py ;;
  esac
  python3 "tb/problem_gen/$GENERATOR" --spec "$SPEC"
fi
if [ "$TEST" = pll_wrapper ] && [ -n "${PLL_SIM_MODEL:-}" ]; then
  test -r "$PLL_SIM_MODEL"
  # Use exactly one PLL implementation, never a DC black-box declaration.
  sed '\|^./tb/pll_cfg/pll_functional_model.sv$|d' "$LIST" > filelist_vendor_pll.f
  printf '%s\n' "$PLL_SIM_MODEL" >> filelist_vendor_pll.f
  LIST=filelist_vendor_pll.f
  echo "Vendor PLL model: $PLL_SIM_MODEL"
else
  echo "Wrapper tests use an ideal behavioral PLL and functional pad stubs, not analog models."
fi
sha256sum new_version/*.sv common/*.sv > source_sha256.txt
vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    -f "$LIST" -top "$TOP" -o ./simv -l compile.log
./simv -l "sim_${TEST}.log"
grep -Eq '^\[TB_[^]]+\] PASS' "sim_${TEST}.log"
echo "PASS: $WORK/rtl/sim_${TEST}.log End: $(date)"
