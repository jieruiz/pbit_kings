#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -J chi_pipe_extra
#SBATCH -o chi-pipe-extra-%j.out
#SBATCH -e chi-pipe-extra-%j.err

set -Eeo pipefail
trap 'rc=$?; echo "ERROR line=$LINENO exit=$rc command=$BASH_COMMAND" >&2; exit $rc' ERR
if [[ -z "${SLURM_JOB_ID:-}" ]]; then echo "Submit with sbatch" >&2; exit 1; fi
set +u
source ~/.bashrc
set -euo pipefail

ROOT="${PROJECT_PATH:-${SLURM_SUBMIT_DIR}}"
TEST="${TEST:-${1:-uart_end_to_end}}"
case "$TEST" in
  uart_end_to_end)
    TOP=tb_uart_end_to_end
    MARKER='[TB_UART_END_TO_END] PASS'
    SOURCES=$'-f filelist_pbit_top_chimera.f\ntb/tb_uart_end_to_end.sv'
    ;;
  uart_full_snapshot)
    TOP=tb_uart_full_snapshot
    MARKER='[TB_UART_FULL_SNAPSHOT] PASS'
    SOURCES=$'-f filelist_pbit_top_chimera.f\ntb/chimera_problem_harness.sv\ntb/tb_uart_full_snapshot.sv'
    ;;
  config_boundaries)
    TOP=tb_config_boundaries
    MARKER='[TB_CONFIG_BOUNDARIES] PASS'
    SOURCES=$'-f filelist_pbit_top_chimera.f\ntb/chimera_problem_harness.sv\ntb/tb_config_boundaries.sv'
    ;;
  error_paths)
    TOP=tb_error_paths
    MARKER='[TB_ERROR_PATHS] PASS'
    SOURCES=$'-f filelist_pbit_top_chimera.f\ntb/chimera_problem_harness.sv\ntb/tb_error_paths.sv'
    ;;
  probability_modes)
    TOP=tb_probability_modes
    MARKER='[TB_PROBABILITY_MODES] PASS'
    SOURCES=$'-timescale=1ns/1ps\nnew_version/pbit_pkg.sv\ncommon/dff_sets.sv\nnew_version/edge_prob_compare.sv\nnew_version/pbit_edge_contrib2.sv\nnew_version/edge_compare6.sv\nnew_version/mac.sv\ntb/tb_probability_modes.sv'
    ;;
  mac_signed_lanes)
    TOP=tb_mac_signed_lanes
    MARKER='[TB_MAC_SIGNED_LANES] PASS'
    SOURCES=$'-timescale=1ns/1ps\nnew_version/pbit_pkg.sv\ncommon/dff_sets.sv\nnew_version/edge_prob_compare.sv\nnew_version/pbit_edge_contrib2.sv\nnew_version/edge_compare6.sv\nnew_version/mac.sv\ntb/tb_mac_signed_lanes.sv'
    ;;
  topology_routing)
    TOP=tb_topology_routing
    MARKER='[TB_TOPOLOGY_ROUTING] PASS'
    SOURCES=$'-f filelist_pbit_top_chimera.f\ntb/chimera_problem_harness.sv\ntb/tb_topology_routing.sv'
    ;;
  *) echo "Unknown TEST=$TEST" >&2; exit 2 ;;
esac

grep -Fq 'contrib_ff' "$ROOT/rtl/new_version/mac.sv"
grep -Fq 'bias_rand_w < bias_prob_i' "$ROOT/rtl/new_version/mac.sv"
grep -Fq 'rand_i <= prob_i' "$ROOT/rtl/new_version/edge_prob_compare.sv"

WORK="$ROOT/sim_pipeline/extra/${TEST}_${SLURM_JOB_ID}"
mkdir -p "$(dirname "$WORK")"
[[ ! -e "$WORK" ]] || { echo "Refusing to overwrite $WORK" >&2; exit 2; }
mkdir "$WORK"
cp -a "$ROOT/rtl" "$WORK/rtl"
cp "$ROOT/pipeline_tb/extra/tb_${TEST}.sv" "$WORK/rtl/tb/tb_${TEST}.sv"
if [[ "$TEST" == config_boundaries || "$TEST" == error_paths || "$TEST" == topology_routing || "$TEST" == uart_full_snapshot ]]; then
  cp "$ROOT/pipeline_tb/chimera_problem/chimera_problem_harness.sv" \
     "$WORK/rtl/tb/chimera_problem_harness.sv"
fi
printf '%s\n' "$SOURCES" > "$WORK/rtl/test.f"
cd "$WORK/rtl"

echo "Node=$(hostname) Job=${SLURM_JOB_ID} test=$TEST Start=$(date) Work=$PWD"
sha256sum new_version/*.sv common/*.sv "tb/tb_${TEST}.sv" > input_sha256.txt
vcs -full64 -sverilog -debug_access+all -kdb -f test.f -top "$TOP" \
    -o "./simv_${TEST}" -l compile.log
"./simv_${TEST}" -l sim.log
grep -Fq "$MARKER" sim.log
echo "PASS: test=$TEST output=$WORK/rtl End=$(date)"
