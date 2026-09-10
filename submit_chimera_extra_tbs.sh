#!/bin/bash
# Submit the three independent UART/count/error regressions.

set -eo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

for test_name in uart_end_to_end config_boundaries error_paths; do
    job_id=$(sbatch --parsable --job-name="ch_${test_name}" \
        run_chimera_extra_tb_sbatch.sh "$test_name")
    echo "$test_name job=$job_id"
done
