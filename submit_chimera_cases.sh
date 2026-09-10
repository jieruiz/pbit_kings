#!/bin/bash
# Submit one isolated RTL simulation job for each representative Chimera case.

set -eo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
runs=${RUNS:-3}
sweeps=${SWEEPS:-500}
majority=${MAJORITY:-5}

case "$runs" in *[!0-9]*|'') echo "RUNS must be a positive integer" >&2; exit 2;; esac
case "$sweeps" in *[!0-9]*|'') echo "SWEEPS must be a positive integer" >&2; exit 2;; esac
case "$majority" in *[!0-9]*|'') echo "MAJORITY must be a positive integer" >&2; exit 2;; esac
(( runs >= 1 )) || { echo "RUNS must be at least 1" >&2; exit 2; }
(( sweeps >= 1 )) || { echo "SWEEPS must be at least 1" >&2; exit 2; }
(( majority >= 1 && majority <= 32 )) || { echo "MAJORITY must be in 1..32" >&2; exit 2; }

cd "$script_dir"

echo "Submitting Chimera suite: runs=$runs sweeps=$sweeps majority=$majority"
for case_name in \
    random_cut_n0096_s401 \
    dense_cut_n0024_s101 \
    random3_cut_n0096_s901 \
    native_cut_n0448_s201 \
    random_sat3_n0024_s401 \
    uniform_sat3_n0060_s501 \
    random_sat4_n0012_s401
do
    job_id=$(sbatch --parsable --job-name="ch_${case_name}" run_chimera_problem_sbatch.sh \
        "$case_name" --runs "$runs" --sweeps "$sweeps" --majority "$majority")
    echo "$case_name job=$job_id"
done

echo "Submitted all representative Chimera cases."
