#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH -J pbit_chimera_sim
#SBATCH -o pbit-sim-%j.out
#SBATCH -e pbit-sim-%j.err
set -eo pipefail
set +u
source ~/.bashrc
set -u
export PROJECT_PATH="${PROJECT_PATH:-${SLURM_SUBMIT_DIR:-$PWD}}"
TEST="${TEST:-rw}"
case "$TEST" in
  rw)
    LIST=filelist_rw_basic.f
    TOP=tb
    TB_SOURCE=tb/tb_rw_basic.sv
    PASS_PATTERN='^PASS rw_basic:'
    ;;
  array_timing)
    LIST=filelist_array_timing.f
    TOP=tb_array_timing
    TB_SOURCE=tb/tb_array_timing.sv
    PASS_PATTERN='^\[TB_ARRAY_TIMING\] PASS '
    ;;
  *) echo "Unknown TEST=$TEST; supported tests: rw, array_timing" >&2; exit 2 ;;
esac
test -r "$PROJECT_PATH/rtl/new_version/pbit_pkg.sv"
if [ ! -r "$PROJECT_PATH/rtl/$LIST" ] || [ ! -r "$PROJECT_PATH/rtl/$TB_SOURCE" ]; then
  echo "Missing test files for TEST=$TEST in $PROJECT_PATH/rtl" >&2
  exit 2
fi
if [ "$TEST" = array_timing ] && [ ! -r "$PROJECT_PATH/rtl/tb/tanh_lut_reference.mem" ]; then
  echo "Missing tb/tanh_lut_reference.mem for TEST=array_timing" >&2
  exit 2
fi
JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$PROJECT_PATH/sim_runs/${TEST}_${JOB}"
mkdir -p "$WORK"
# Each job owns its RTL snapshot and all VCS artifacts.
cp -a "$PROJECT_PATH/rtl" "$WORK/rtl"
cd "$WORK/rtl"
echo "Node: $(hostname) Test: $TEST Start: $(date) Work: $PWD"
sha256sum new_version/*.sv common/*.sv > source_sha256.txt
vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    -f "$LIST" -top "$TOP" -o ./simv -l compile.log
./simv -l "sim_${TEST}.log"
if ! grep -Eq "$PASS_PATTERN" "sim_${TEST}.log"; then
  echo "FAIL: expected success marker missing from $WORK/rtl/sim_${TEST}.log" >&2
  exit 1
fi
echo "PASS: $WORK/rtl/sim_${TEST}.log End: $(date)"
