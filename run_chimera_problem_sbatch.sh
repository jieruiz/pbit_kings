#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
#SBATCH --mem=16G
#SBATCH -J chimera_problem
#SBATCH -o chimera-%j.out
#SBATCH -e chimera-%j.err

set -Eeo pipefail
trap 'rc=$?; echo "ERROR: command failed at line $LINENO (exit=$rc): $BASH_COMMAND" >&2; exit $rc' ERR
set +u
source ~/.bashrc
set -u
root="${CHIMERA_SOURCE_ROOT:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}}"
case_name="${1:-random_cut_n0096_s401}"
if (( $# > 0 )); then shift; fi
[[ "$case_name" =~ ^[a-zA-Z0-9_]+$ ]] || { echo "Invalid case name" >&2; exit 2; }
[[ -f "$root/rtl/tb/chimera_problem_gen/gen_chimera_problem.py" ]] || {
    echo "Submit from the Chimera project root, or set CHIMERA_SOURCE_ROOT" >&2; exit 2;
}
command -v python3
python3 --version
command -v vcs
job="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)}"
work="$root/sim_chimera/$case_name/$job"
mkdir -p "$work"
[[ ! -e "$work/rtl" ]] || { echo "Refusing to overwrite existing job $work" >&2; exit 2; }
mkdir "$work/rtl"
cp -a "$root/rtl/." "$work/rtl/"
cd "$work/rtl"
echo "Node=$(hostname) job=$job case=$case_name output=$work/rtl"
python3 tb/chimera_problem_gen/gen_chimera_problem.py "$@" --case "$case_name" --output tb/chimera_generated
sha256sum new_version/*.sv common/dff_sets.sv tb/chimera_generated/* > input_sha256.txt
echo "[CHIMERA_JOB] Compiling testbench"
vcs -full64 -sverilog -f filelist_run_chimera_problem.f -top tb_chimera_problem \
    -o ./simv_chimera -l compile_chimera.log

# Use positional parameters instead of an empty array. CentOS 7 ships an old
# Bash that treats "${empty_array[@]}" as unbound when nounset is enabled.
set --
if [[ "${TRANSPORT:-bus}" == uart ]]; then
    set -- "$@" +UART
elif [[ "${TRANSPORT:-bus}" != bus ]]; then
    echo "TRANSPORT must be bus or uart" >&2; exit 2
fi
if [[ "${UART_SMOKE:-0}" == 1 ]]; then
    set -- "$@" +UART_SMOKE
elif [[ "${UART_SMOKE:-0}" != 0 ]]; then
    echo "UART_SMOKE must be 0 or 1" >&2; exit 2
fi
if [[ -n "${MIN_SCORE:-}" ]]; then set -- "$@" "+MIN_SCORE=$MIN_SCORE"; fi
echo "[CHIMERA_JOB] Running simulation transport=${TRANSPORT:-bus}"
./simv_chimera "$@" -l sim_chimera.log
grep -Fq '[TB_CHIMERA_PROBLEM] PASS' sim_chimera.log
echo "[CHIMERA_JOB] Checking generated scores"
python3 tb/chimera_problem_gen/check_results.py | tee python_score_check.log
echo "Complete: $work/rtl"
