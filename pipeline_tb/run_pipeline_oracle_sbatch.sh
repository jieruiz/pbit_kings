#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -J chi_pipe_oracle
#SBATCH -o chi-pipe-oracle-%j.out
#SBATCH -e chi-pipe-oracle-%j.err
set -Eeo pipefail
trap 'rc=$?; echo "ERROR line=$LINENO exit=$rc command=$BASH_COMMAND" >&2; exit $rc' ERR
if [[ -z "${SLURM_JOB_ID:-}" ]]; then echo "Submit with sbatch" >&2; exit 1; fi
set +u
source ~/.bashrc
set -euo pipefail

ROOT="${PROJECT_PATH:-${SLURM_SUBMIT_DIR}}"
CASE_NAME="${CASE_NAME:-dense_cut_n0024_s101}"
SWEEPS="${SWEEPS:-32}"
RUNS="${RUNS:-1}"
MAJORITY="${MAJORITY:-5}"
SEED_MASTER="${SEED_MASTER:-2461}"
INIT_SEED="${INIT_SEED:-314592}"
SCHEDULE="${SCHEDULE:-linear}"
I0_START="${I0_START:-0.1}"
I0_END="${I0_END:-4.0}"
FIXTURE="$ROOT/pipeline_tb/chimera_problem/oracle_fixtures/dense_cut_n0024_s101_s32_r1_m5"

if [[ "$CASE_NAME" != dense_cut_n0024_s101 || "$SWEEPS" != 32 || \
      "$RUNS" != 1 || "$MAJORITY" != 5 || "$SEED_MASTER" != 2461 || \
      "$INIT_SEED" != 314592 || "$SCHEDULE" != linear || \
      "$I0_START" != 0.1 || "$I0_END" != 4.0 ]]; then
    echo "This static-oracle regression requires case=dense_cut_n0024_s101, sweeps=32," >&2
    echo "runs=1, majority=5, seeds=2461/314592, linear I0=0.1..4.0." >&2
    exit 2
fi
[[ -d "$FIXTURE" ]] || { echo "Missing static oracle fixture: $FIXTURE" >&2; exit 2; }

grep -Fq 'contrib_ff' "$ROOT/rtl/new_version/mac.sv"
grep -Fq 'bias_rand_w < bias_prob_i' "$ROOT/rtl/new_version/mac.sv"
grep -Fq 'rand_i <= prob_i' "$ROOT/rtl/new_version/edge_prob_compare.sv"
grep -Fq 'threshold_load_q' "$ROOT/rtl/new_version/pbit_bank.sv"

JOB="${SLURM_JOB_ID}"
WORK="$ROOT/sim_pipeline/oracle/${CASE_NAME}_${JOB}"
mkdir -p "$(dirname "$WORK")"
mkdir "$WORK"
cp -a "$ROOT/rtl" "$WORK/rtl"
cp "$ROOT/pipeline_tb/chimera_problem/chimera_problem_harness.sv" "$WORK/rtl/tb/chimera_pipeline_problem_harness.sv"
cp "$ROOT/pipeline_tb/chimera_problem/tb_run_chimera_problem.sv" "$WORK/rtl/tb/tb_chimera_pipeline_problem.sv"
cp "$ROOT/pipeline_tb/chimera_problem/filelist_problem.f" "$WORK/rtl/filelist_pipeline_problem.f"
mkdir "$WORK/rtl/tb/chimera_pipeline_generated"
cp -a "$FIXTURE/." "$WORK/rtl/tb/chimera_pipeline_generated/"

cd "$WORK/rtl"
echo "Node=$(hostname) Job=$JOB case=$CASE_NAME Start=$(date) Work=$PWD"
echo "Using precomputed static oracle: $FIXTURE"

for generated_file in problem.svh manifest.json chain_start.mem chain_nodes.mem \
    graph_a.mem graph_b.mem graph_w.mem clause_start.mem literals.mem sweep_i0.mem \
    config_0.mem initial_0.mem oracle_score.mem oracle_best.mem oracle_broken.mem \
    oracle_ties.mem oracle_i0.mem oracle_cycles.mem oracle_spins.mem oracle_history.csv; do
    [[ -f "tb/chimera_pipeline_generated/$generated_file" ]] || {
        echo "Missing generated input: tb/chimera_pipeline_generated/$generated_file" >&2
        exit 2
    }
done

sha256sum new_version/*.sv common/*.sv tb/chimera_pipeline_generated/* > input_sha256.txt
vcs -full64 -sverilog -f filelist_pipeline_problem.f -top tb_chimera_pipeline_problem \
    -o ./simv_chimera_pipeline -l compile.log
sim_args=(+DATA_DIR=tb/chimera_pipeline_generated +CHECK_ORACLE)
if [[ -n "${MIN_SCORE:-}" ]]; then
    sim_args+=("+MIN_SCORE=$MIN_SCORE")
fi
./simv_chimera_pipeline "${sim_args[@]}" -l sim.log
grep -Fq '[CHIMERA_PIPELINE_ORACLE] PASS' sim.log
grep -Fq '[TB_CHIMERA_PIPELINE_PROBLEM] PASS' sim.log
echo "PASS: $WORK/rtl End=$(date)"
