#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH -J pbit_reg80
#SBATCH -o pbit-regression-80x80-%j.out
#SBATCH -e pbit-regression-80x80-%j.err

set -eo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/public3/home/t6s011227/pbit_kings_yanzenan_latest_260905_io_wrapper_80x80}"
RTL_DIR="${PROJECT_ROOT}/rtl"
TEST_CASES=(
    run_3x3
    run_3x3_majority
    run_3x3_maxcut
    run_ksat_10v40c
    run_w50_maxcut
)

if [[ -n "${TEST_CASE:-}" ]]; then
    CASE_NAME="${TEST_CASE}"
elif [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]] &&
     (( SLURM_ARRAY_TASK_ID >= 0 && SLURM_ARRAY_TASK_ID < ${#TEST_CASES[@]} )); then
    CASE_NAME="${TEST_CASES[SLURM_ARRAY_TASK_ID]}"
else
    echo "Set TEST_CASE or submit this script with --array=0-4." >&2
    exit 2
fi

case "${CASE_NAME}" in
    run_3x3)
        FILELIST="filelist_run_3x3.f"
        PASS_MARKER="[TB_RUN_3X3] PASS"
        ;;
    run_3x3_majority)
        FILELIST="filelist_run_3x3_majority.f"
        PASS_MARKER="[TB_RUN_3X3_MAJORITY] PASS"
        ;;
    run_3x3_maxcut)
        FILELIST="filelist_run_3x3_maxcut.f"
        PASS_MARKER="[TB_RUN_3X3_MAXCUT] PASS"
        ;;
    run_ksat_10v40c)
        FILELIST="filelist_run_ksat_10v40c.f"
        PASS_MARKER="[TB_RUN_KSAT_10V40C] PASS"
        ;;
    run_w50_maxcut)
        FILELIST="filelist_run_w50_maxcut.f"
        PASS_MARKER="[TB_RUN_W50_MAXCUT] PASS"
        ;;
    *)
        echo "Unknown TEST_CASE: ${CASE_NAME}" >&2
        exit 2
        ;;
esac

RUN_ID="${SLURM_ARRAY_JOB_ID:-${SLURM_JOB_ID:-manual}}_${SLURM_ARRAY_TASK_ID:-0}"
RUN_DIR="${RTL_DIR}/sim_runs_80x80/${CASE_NAME}/${RUN_ID}"
mkdir -p "${RUN_DIR}"

set +u
source ~/.bashrc
set -u

echo "Node: $(hostname)"
echo "Job ID: ${SLURM_JOB_ID:-manual}"
echo "Case: ${CASE_NAME}"
echo "Start: $(date)"
echo "Run directory: ${RUN_DIR}"

cd "${RTL_DIR}"
vcs -full64 -sverilog -debug_access+all -kdb \
    -Mdir="${RUN_DIR}/csrc" \
    -f "${FILELIST}" \
    -o "${RUN_DIR}/simv"

cd "${RUN_DIR}"
./simv -l sim.log
grep -Fq "${PASS_MARKER}" sim.log

echo "PASS: ${PASS_MARKER}"
echo "Log: ${RUN_DIR}/sim.log"
echo "End: $(date)"
