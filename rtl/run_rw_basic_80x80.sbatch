#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH -J pbit_rw_80
#SBATCH -o rw-basic-80x80-%j.out
#SBATCH -e rw-basic-80x80-%j.err

set -eo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/public3/home/t6s011227/pbit_kings_yanzenan_latest_260905_io_wrapper_80x80}"
RTL_DIR="${PROJECT_ROOT}/rtl"
RUN_TAG="${SLURM_JOB_ID:-manual_$$}"
SIMV="simv_rw_basic_80x80_${RUN_TAG}"
CDIR="csrc_rw_basic_80x80_${RUN_TAG}"
SIM_LOG="sim_rw_basic_80x80_${RUN_TAG}.log"

cd "${RTL_DIR}"

set +u
source ~/.bashrc
set -u

echo "Node: $(hostname)"
echo "Job ID: ${SLURM_JOB_ID:-manual}"
echo "Start: $(date)"
echo "RTL: ${RTL_DIR}"

vcs -full64 -sverilog -debug_access+all -kdb \
    -Mdir="${CDIR}" \
    -f filelist_rw_basic.f \
    -o "./${SIMV}"

"./${SIMV}" -l "${SIM_LOG}"
grep -q '\[TB_RW_BASIC\] PASS' "${SIM_LOG}"

echo "PASS log: ${RTL_DIR}/${SIM_LOG}"
echo "End: $(date)"
