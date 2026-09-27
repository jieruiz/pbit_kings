#!/bin/bash
# Submit the complete latest-pipeline RTL regression as independent Slurm jobs.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$script_dir/.." && pwd)
cd "$root"

runs=${RUNS:-3}
sweeps=${SWEEPS:-500}
majority=${MAJORITY:-5}
for value in "$runs" "$sweeps" "$majority"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "RUNS, SWEEPS and MAJORITY must be positive integers" >&2; exit 2; }
done
(( majority <= 32 )) || { echo "MAJORITY must be <=32" >&2; exit 2; }

submit() {
  local label=$1
  shift
  local job_id
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    printf '[DRY_RUN] %-26s sbatch' "$label"
    printf ' %q' "$@"
    printf '\n'
    return
  fi
  job_id=$(sbatch --parsable "$@")
  printf '%-36s job=%s\n' "$label" "$job_id"
}

submit basic_rw --job-name=chi_pipe_rw --export=ALL,TEST=rw pipeline_tb/run_sbatch.sh
submit basic_run3x3 --job-name=chi_pipe_run3x3 --export=ALL,TEST=run3x3 pipeline_tb/run_sbatch.sh

for test_name in uart_end_to_end uart_full_snapshot config_boundaries error_paths probability_modes mac_signed_lanes topology_routing; do
  submit "extra_${test_name}" --job-name="cp_${test_name}" \
    --export="ALL,TEST=${test_name}" pipeline_tb/run_extra_sbatch.sh
done

for case_name in \
  random_cut_n0096_s401 \
  dense_cut_n0024_s101 \
  random3_cut_n0096_s901 \
  native_cut_n0448_s201 \
  random_sat3_n0024_s401 \
  uniform_sat3_n0060_s501 \
  random_sat4_n0012_s401
do
  submit "problem_${case_name}" --job-name="cp_${case_name}" \
    --export="ALL,CASE_NAME=${case_name},RUNS=${runs},SWEEPS=${sweeps},MAJORITY=${majority}" \
    pipeline_tb/run_chimera_problem_sbatch.sh
done

if [[ "${DRY_RUN:-0}" == 1 ]]; then
  echo "Dry run complete: 16 independent regression jobs checked."
else
  echo "Submitted 16 independent regression jobs."
fi
