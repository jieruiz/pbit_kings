#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
#SBATCH --mem=16G
#SBATCH -J chimera_extra_tb
#SBATCH -o chimera-extra-%j.out
#SBATCH -e chimera-extra-%j.err

set -Eeo pipefail
trap 'rc=$?; echo "ERROR: command failed at line $LINENO (exit=$rc): $BASH_COMMAND" >&2; exit $rc' ERR
set +u
source ~/.bashrc
set -u

root="${CHIMERA_SOURCE_ROOT:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}}"
test_name="${1:-uart_end_to_end}"
case "$test_name" in
    uart_end_to_end)
        filelist=filelist_uart_end_to_end.f
        top=tb_uart_end_to_end
        ;;
    config_boundaries)
        filelist=filelist_config_boundaries.f
        top=tb_config_boundaries
        ;;
    error_paths)
        filelist=filelist_error_paths.f
        top=tb_error_paths
        ;;
    *)
        echo "Unknown test '$test_name'; use uart_end_to_end, config_boundaries or error_paths" >&2
        exit 2
        ;;
esac

[[ -f "$root/rtl/$filelist" ]] || {
    echo "Submit from the Chimera project root, or set CHIMERA_SOURCE_ROOT" >&2
    exit 2
}
command -v vcs

job="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)}"
work="$root/sim_chimera_extra/$test_name/$job"
mkdir -p "$work"
[[ ! -e "$work/rtl" ]] || { echo "Refusing to overwrite $work/rtl" >&2; exit 2; }
mkdir "$work/rtl"
cp -a "$root/rtl/." "$work/rtl/"
cd "$work/rtl"

echo "[CHIMERA_EXTRA] node=$(hostname) job=$job test=$test_name output=$work/rtl"
vcs -full64 -sverilog -debug_access+all -kdb -f "$filelist" -top "$top" \
    -o "./simv_$test_name" -l "compile_$test_name.log"
"./simv_$test_name" -l "sim_$test_name.log"
grep -Fq "[TB_${test_name^^}] PASS" "sim_$test_name.log"
echo "[CHIMERA_EXTRA] PASS test=$test_name output=$work/rtl"
