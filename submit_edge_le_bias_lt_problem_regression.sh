#!/bin/bash
# Re-run a compact subset of the established Chimera suite with identical seeds.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

runs=3
sweeps=500
majority=5
seed_master=2461
init_seed=314592

echo "Submitting edge<= / bias< comparison suite"
echo "runs=$runs sweeps=$sweeps majority=$majority seed_master=$seed_master init_seed=$init_seed"

for case_name in \
    random_cut_n0096_s401 \
    native_cut_n0448_s201 \
    random_sat3_n0024_s401
do
    job_id=$(sbatch --parsable --job-name="elbl_${case_name}" \
        run_chimera_problem_sbatch.sh "$case_name" \
        --runs "$runs" \
        --sweeps "$sweeps" \
        --majority "$majority" \
        --seed-master "$seed_master" \
        --init-seed "$init_seed")
    echo "$case_name job=$job_id"
done
