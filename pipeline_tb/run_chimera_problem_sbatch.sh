#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -J chi_pipe_problem
#SBATCH -o chi-pipe-problem-%j.out
#SBATCH -e chi-pipe-problem-%j.err
set -Eeo pipefail
trap 'rc=$?; echo "ERROR line=$LINENO exit=$rc command=$BASH_COMMAND" >&2; exit $rc' ERR
if [[ -z "${SLURM_JOB_ID:-}" ]]; then echo "Submit with sbatch" >&2; exit 1; fi
set +u
source ~/.bashrc
set -euo pipefail
ROOT="${PROJECT_PATH:-${SLURM_SUBMIT_DIR}}"
CASE_NAME="${CASE_NAME:-${1:-native_cut_n0448_s201}}"
SWEEPS="${SWEEPS:-500}"
RUNS="${RUNS:-3}"
MAJORITY="${MAJORITY:-5}"
case "$CASE_NAME" in
  random_cut_n0096_s401|dense_cut_n0024_s101|random3_cut_n0096_s901|native_cut_n0448_s201|random_sat3_n0024_s401|uniform_sat3_n0060_s501|random_sat4_n0012_s401) ;;
  *) echo "Unknown CASE_NAME=$CASE_NAME" >&2; exit 2 ;;
esac
for value in "$SWEEPS" "$RUNS" "$MAJORITY"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid positive integer: $value" >&2; exit 2; }
done
(( MAJORITY <= 32 )) || { echo "MAJORITY must be <=32" >&2; exit 2; }
grep -Fq 'contrib_ff' "$ROOT/rtl/new_version/mac.sv"
grep -Fq 'bias_rand_w < bias_prob_i' "$ROOT/rtl/new_version/mac.sv"
grep -Fq 'rand_i <= prob_i' "$ROOT/rtl/new_version/edge_prob_compare.sv"
grep -Fq 'threshold_load_q' "$ROOT/rtl/new_version/pbit_bank.sv"
JOB="${SLURM_JOB_ID}"
WORK="$ROOT/sim_pipeline/problems/${CASE_NAME}_${JOB}"
mkdir -p "$(dirname "$WORK")"
mkdir "$WORK"
cp -a "$ROOT/rtl" "$WORK/rtl"
cp "$ROOT/pipeline_tb/chimera_problem/chimera_problem_harness.sv" "$WORK/rtl/tb/chimera_pipeline_problem_harness.sv"
cp "$ROOT/pipeline_tb/chimera_problem/tb_run_chimera_problem.sv" "$WORK/rtl/tb/tb_chimera_pipeline_problem.sv"
cp "$ROOT/pipeline_tb/chimera_problem/filelist_problem.f" "$WORK/rtl/filelist_pipeline_problem.f"
cp -a "$ROOT/pipeline_tb/chimera_problem/problem_gen" "$WORK/rtl/tb/chimera_pipeline_problem_gen"
cd "$WORK/rtl"
echo "Node=$(hostname) Job=$JOB case=$CASE_NAME Start=$(date) Work=$PWD"
python3 tb/chimera_pipeline_problem_gen/gen_chimera_problem.py \
    --case "$CASE_NAME" \
    --output tb/chimera_pipeline_generated \
    --sweeps "$SWEEPS" --runs "$RUNS" --majority "$MAJORITY" \
    --seed-master "${SEED_MASTER:-2461}" --init-seed "${INIT_SEED:-314592}" \
    --schedule "${SCHEDULE:-linear}" --i0-start "${I0_START:-0.1}" --i0-end "${I0_END:-4.0}"
for generated_file in problem.svh manifest.json chain_start.mem chain_nodes.mem \
    graph_a.mem graph_b.mem graph_w.mem clause_start.mem literals.mem sweep_i0.mem \
    config_0.mem initial_0.mem; do
    [[ -f "tb/chimera_pipeline_generated/$generated_file" ]] || {
        echo "Missing generated input: tb/chimera_pipeline_generated/$generated_file" >&2
        exit 2
    }
done
sha256sum new_version/*.sv common/*.sv tb/chimera_pipeline_generated/* > input_sha256.txt
vcs -full64 -sverilog -f filelist_pipeline_problem.f -top tb_chimera_pipeline_problem \
    -o ./simv_chimera_pipeline -l compile.log
set -- +DATA_DIR=tb/chimera_pipeline_generated
if [[ -n "${MIN_SCORE:-}" ]]; then set -- "+MIN_SCORE=$MIN_SCORE"; fi
./simv_chimera_pipeline "$@" -l sim.log
grep -Fq '[TB_CHIMERA_PIPELINE_PROBLEM] PASS' sim.log
python3 tb/chimera_pipeline_problem_gen/check_results.py \
    --data tb/chimera_pipeline_generated --states chimera_states.txt --csv chimera_sweeps.csv \
    | tee python_score_check.log
grep -Fq '[PY_SCORE_CHECK] PASS' python_score_check.log
echo "PASS: $WORK/rtl End=$(date)"
