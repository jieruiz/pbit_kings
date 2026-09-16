#!/bin/bash
# Submit one exhaustive probability test and one representative biased problem.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

probability_job=$(sbatch --parsable --job-name=ch_elbl_probability \
    run_chimera_extra_tb_sbatch.sh probability_modes)
problem_job=$(sbatch --parsable --job-name=ch_elbl_sat3 \
    run_chimera_problem_sbatch.sh random_sat3_n0024_s401 \
    --runs 1 --sweeps 128 --majority 5)

echo "probability_modes job=$probability_job"
echo "random_sat3_n0024_s401 job=$problem_job"
