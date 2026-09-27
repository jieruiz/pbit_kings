#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -J pbit_g500_mc
#SBATCH -o gate500-maxcut-%j.out
#SBATCH -e gate500-maxcut-%j.err

set -Eeo pipefail
trap 'rc=$?; echo "ERROR line=$LINENO exit=$rc command=$BASH_COMMAND" >&2; exit $rc' ERR
set +u
source ~/.bashrc
set -u

if [ -n "${GATE_SIM_SOURCE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$GATE_SIM_SOURCE_DIR" && pwd)"
elif [ -n "${SLURM_SUBMIT_DIR:-}" ] && \
     [ -r "$SLURM_SUBMIT_DIR/uart_host.sv" ]; then
  SCRIPT_DIR="$(cd "$SLURM_SUBMIT_DIR" && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${GATE_SIM_ROOT:-$SCRIPT_DIR}"
MODE="${MODE:-sdf}"
PLL_CFG_HEX="${PLL_CFG_HEX:-0228}"
DEFAULT_DC_RUN="/public3/home/t6s011227/pbit_chimera_pipeline_20260920/dc_500MHz_20_ss125_fanout32/dc_result/pbit_io_wrapper_chimera_pipeline_bias_lt_20x20_3200pbit_500MHz_ss_v1p08_125c_fanout32_fixed_area/37408821_20x20_3200pbit_500MHz"
DC_RUN="${DC_RUN:-$DEFAULT_DC_RUN}"
NETLIST="${NETLIST:-}"
SDF="${SDF:-}"
PLL_MODEL="${PLL_MODEL:-/public3/home/t6s011227/PLL_new_ip/PLL_20260916/verilog/PLL_TOP.v}"
IO_MODEL="${IO_MODEL:-/public3/home/t6s011227/ICsprout_55LLULP1225_IO_0901/ICsprout_55LLULP1225_IO_0901/IC055L_GPIO3P3V_CDG_v1.1a/verilog/ic055l_gpio3p3v_cdg_v1p1a/IC055L_GPIO3P3V_CDG.v}"
STD_MODEL_DIR="${STD_MODEL_DIR:-/public3/home/t6s011227/ICsprout_55LLULP1225_STD_0818/ICsprout55_SC9T_BASIC_SVT/0.1/verilog}"
STD_MODEL="${STD_MODEL:-$STD_MODEL_DIR/ICsprout55_9TSVT_basic.v}"
GENERATOR="$PROJECT_ROOT/pipeline_tb/chimera_problem/problem_gen/gen_chimera_problem.py"

case "$MODE" in
  zero|sdf) ;;
  *) echo "MODE must be zero or sdf" >&2; exit 2 ;;
esac

test -d "$DC_RUN"
if [ -z "$NETLIST" ]; then
  mapfile -t NETLIST_CANDIDATES < <(find "$DC_RUN" -maxdepth 1 -type f \
      -name '*_gate.v' ! -name '*_gate_pg.v' | sort)
  if [ "${#NETLIST_CANDIDATES[@]}" -ne 1 ]; then
    printf 'Expected one non-PG *_gate.v under %s, found %d\n' \
        "$DC_RUN" "${#NETLIST_CANDIDATES[@]}" >&2
    printf '%s\n' "${NETLIST_CANDIDATES[@]}" >&2
    exit 2
  fi
  NETLIST="${NETLIST_CANDIDATES[0]}"
fi
if [ "$MODE" = sdf ] && [ -z "$SDF" ]; then
  mapfile -t SDF_CANDIDATES < <(find "$DC_RUN" -maxdepth 1 -type f \
      -name '*.sdf' | sort)
  if [ "${#SDF_CANDIDATES[@]}" -ne 1 ]; then
    printf 'Expected one *.sdf under %s, found %d\n' \
        "$DC_RUN" "${#SDF_CANDIDATES[@]}" >&2
    printf '%s\n' "${SDF_CANDIDATES[@]}" >&2
    exit 2
  fi
  SDF="${SDF_CANDIDATES[0]}"
fi

for file in "$NETLIST" "$PLL_MODEL" "$IO_MODEL" "$STD_MODEL" \
            "$GENERATOR" "$SCRIPT_DIR/uart_host.sv" \
            "$SCRIPT_DIR/gate_pipeline_env.sv" \
            "$SCRIPT_DIR/tb_gate_pipeline_maxcut.sv"; do
  test -r "$file" || { echo "Required file is not readable: $file" >&2; exit 2; }
done
if [ "$MODE" = sdf ]; then
  test -r "$SDF" || { echo "Required SDF is not readable: $SDF" >&2; exit 2; }
fi
if [[ "$(basename "$STD_MODEL")" == *_pg.v ]]; then
  echo "The non-PG gate netlist requires a non-PG standard-cell model" >&2
  exit 2
fi
if grep -Eq '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST"; then
  echo "Unmapped generic cells remain in gate netlist: $NETLIST" >&2
  exit 2
fi

JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$ROOT/sim_runs/gate_pipeline_500_maxcut_${MODE}_${JOB}"
GEN_DIR="$WORK/generated"
mkdir -p "$WORK" "$GEN_DIR"

python3 "$GENERATOR" \
    --case native_cut_n0448_s201 --output "$GEN_DIR" \
    --sweeps 200 --runs 1 --majority 5 \
    --seed-master 2461 --init-seed 314592 \
    --schedule linear --i0-start 0.1 --i0-end 4.0 \
    | tee "$WORK/generate_problem.log"

for generated_file in problem.svh manifest.json config_0.mem initial_0.mem \
    chain_start.mem chain_nodes.mem graph_a.mem graph_b.mem graph_w.mem; do
  test -s "$GEN_DIR/$generated_file" || {
    echo "Missing generated input: $GEN_DIR/$generated_file" >&2
    exit 2
  }
done

cd "$WORK"
if [ "$MODE" = sdf ]; then
  if [[ "$SDF" == *'"'* || "$SDF" == *'\\'* ]]; then
    echo "SDF path contains an unsupported quote or backslash: $SDF" >&2
    exit 2
  fi
  printf 'initial begin\n  $display("[GATE_SDF] annotating MAXIMUM delays: %s");\n  $sdf_annotate("%s", env.dut, , "sdf_annotate.log", "MAXIMUM");\nend\n' \
      "$SDF" "$SDF" > gate_sdf_setup.svh
  COMPILE_OPTIONS=(+allmtm +neg_tchk +delay_mode_path +define+GATE_SDF)
  RUN_OPTIONS=(+maxdelays +sdfverbose)
else
  COMPILE_OPTIONS=(+notimingcheck +delay_mode_zero +define+functional)
  RUN_OPTIONS=()
fi

{
  printf '+incdir+.\n'
  printf '+incdir+%s\n' "$GEN_DIR"
  printf -- '-v %s\n' "$STD_MODEL"
  printf -- '-v %s\n' "$IO_MODEL"
  printf '%s\n' "$PLL_MODEL"
  printf '%s\n' "$NETLIST"
  printf '%s\n' "$SCRIPT_DIR/uart_host.sv"
  printf '%s\n' "$SCRIPT_DIR/gate_pipeline_env.sv"
  printf '%s\n' "$SCRIPT_DIR/tb_gate_pipeline_maxcut.sv"
} > gate_pipeline_maxcut_filelist.f

echo "Node=$(hostname) Job=$JOB Start=$(date)"
echo "Mode=$MODE"
echo "Gate simulation source=$SCRIPT_DIR"
echo "Netlist=$NETLIST"
sha256sum "$NETLIST" | tee netlist_sha256.txt
if [ "$MODE" = sdf ]; then
  echo "SDF=$SDF"
  sha256sum "$SDF" | tee sdf_sha256.txt
fi
sha256sum "$GEN_DIR"/* > generated_sha256.txt
echo "PLL config=0x$PLL_CFG_HEX"
echo "Problem=native_cut_n0448_s201 sweeps=200 majority=5 transport=external UART"

vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    "${COMPILE_OPTIONS[@]}" \
    -f gate_pipeline_maxcut_filelist.f -top tb_gate_pipeline_maxcut \
    -o ./simv_gate_pipeline_maxcut -l compile_gate_pipeline_maxcut.log

./simv_gate_pipeline_maxcut "${RUN_OPTIONS[@]}" \
    +DATA_DIR="$GEN_DIR" +PLL_CFG="$PLL_CFG_HEX" \
    -l sim_gate_pipeline_maxcut_${MODE}.log

if [ "$MODE" = sdf ]; then
  grep -q 'Doing SDF annotation .* Done' "sim_gate_pipeline_maxcut_${MODE}.log"
  if [ -s sdf_annotate.log ]; then
    cp sdf_annotate.log sdf_annotate_maxcut.log
  else
    grep -E 'SDF|annotation|MTM' "sim_gate_pipeline_maxcut_${MODE}.log" \
        > sdf_annotate_maxcut.log || true
  fi
fi
grep -Fq '[TB_GATE_PIPELINE_MAXCUT] PASS' \
    "sim_gate_pipeline_maxcut_${MODE}.log"
printf 'PASS mode=%s case=native_cut_n0448_s201 sweeps=200\n' "$MODE" \
    > MAXCUT_GATE_PASS.txt
echo "MAXCUT GATE PASS: $WORK/MAXCUT_GATE_PASS.txt End=$(date)"
