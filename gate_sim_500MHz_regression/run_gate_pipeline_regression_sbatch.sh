#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -J pbit_g500_reg
#SBATCH -o gate500-reg-%j.out
#SBATCH -e gate500-reg-%j.err

set -eo pipefail
set +u
source ~/.bashrc
set -u

if [ -n "${GATE_REG_SOURCE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$GATE_REG_SOURCE_DIR" && pwd)"
elif [ -n "${SLURM_SUBMIT_DIR:-}" ] && \
     [ -r "$SLURM_SUBMIT_DIR/tb_gate_pipeline_regression.sv" ]; then
  SCRIPT_DIR="$(cd "$SLURM_SUBMIT_DIR" && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

ROOT="${GATE_SIM_ROOT:-$SCRIPT_DIR}"
SHARED_DIR="${GATE_SHARED_DIR:-$(cd "$SCRIPT_DIR/../gate_sim_500MHz" && pwd)}"
TEST="${TEST:-all}"
MODE="${MODE:-max}"
PLL_CFG_HEX="${PLL_CFG_HEX:-0228}"
DEFAULT_DC_RUN="/public3/home/t6s011227/pbit_chimera_pipeline_20260920/dc_500MHz_20_ss125_fanout32/dc_result/pbit_io_wrapper_chimera_pipeline_bias_lt_20x20_3200pbit_500MHz_ss_v1p08_125c_fanout32_fixed_area/37408821_20x20_3200pbit_500MHz"
DC_RUN="${DC_RUN:-$DEFAULT_DC_RUN}"
NETLIST="${NETLIST:-}"
SDF="${SDF:-}"
PLL_MODEL="${PLL_MODEL:-/public3/home/t6s011227/PLL_new_ip/PLL_20260916/verilog/PLL_TOP.v}"
IO_MODEL="${IO_MODEL:-/public3/home/t6s011227/ICsprout_55LLULP1225_IO_0901/ICsprout_55LLULP1225_IO_0901/IC055L_GPIO3P3V_CDG_v1.1a/verilog/ic055l_gpio3p3v_cdg_v1p1a/IC055L_GPIO3P3V_CDG.v}"
STD_MODEL_DIR="${STD_MODEL_DIR:-/public3/home/t6s011227/ICsprout_55LLULP1225_STD_0818/ICsprout55_SC9T_BASIC_SVT/0.1/verilog}"
STD_MODEL="${STD_MODEL:-$STD_MODEL_DIR/ICsprout55_9TSVT_basic.v}"

case "$TEST" in
  all) TESTS=(exact crossbank boundaries recovery) ;;
  exact|crossbank|boundaries|recovery) TESTS=("$TEST") ;;
  *) echo "TEST must be all, exact, crossbank, boundaries or recovery" >&2; exit 2 ;;
esac
case "$MODE" in
  zero|max|min) ;;
  *) echo "MODE must be zero, max or min" >&2; exit 2 ;;
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
if [ "$MODE" != zero ] && [ -z "$SDF" ]; then
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

REQUIRED_FILES=(
  "$NETLIST"
  "$PLL_MODEL"
  "$IO_MODEL"
  "$STD_MODEL"
  "$SHARED_DIR/uart_host.sv"
  "$SHARED_DIR/gate_pipeline_env.sv"
  "$SCRIPT_DIR/tb_gate_pipeline_regression.sv"
)
if [ "$MODE" != zero ]; then
  REQUIRED_FILES+=("$SDF")
fi
for file in "${REQUIRED_FILES[@]}"; do
  test -r "$file" || { echo "Required file is not readable: $file" >&2; exit 2; }
done

if [[ "$(basename "$STD_MODEL")" == *_pg.v ]]; then
  echo "The non-PG gate netlist requires a non-PG standard-cell model" >&2
  exit 2
fi
if grep -Eq '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST"; then
  echo "Unmapped generic cells remain in gate netlist: $NETLIST" >&2
  exit 2
fi
if ! grep -Eq '^module[[:space:]]+pbit_io_wrapper([[:space:]]|\()' "$NETLIST"; then
  echo "Top module pbit_io_wrapper is missing from $NETLIST" >&2
  exit 2
fi

JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$ROOT/sim_runs/gate_pipeline_regression_${MODE}_${TEST}_${JOB}"
mkdir -p "$WORK"
cd "$WORK"

VCS_MODE_ARGS=()
SIM_MODE_ARGS=()
if [ "$MODE" = zero ]; then
  VCS_MODE_ARGS=(+notimingcheck +delay_mode_zero)
else
  if [[ "$SDF" == *'"'* || "$SDF" == *'\\'* ]]; then
    echo "SDF path contains an unsupported quote or backslash: $SDF" >&2
    exit 2
  fi
  if [ "$MODE" = max ]; then
    SDF_MTM=MAXIMUM
    SIM_MODE_ARGS=(+maxdelays +sdfverbose)
  else
    SDF_MTM=MINIMUM
    SIM_MODE_ARGS=(+mindelays +sdfverbose)
  fi
  printf 'initial begin\n  $display("[GATE_SDF] annotating %s delays: %s");\n  $sdf_annotate("%s", env.dut, , "sdf_annotate.log", "%s");\nend\n' \
      "$SDF_MTM" "$SDF" "$SDF" "$SDF_MTM" > gate_sdf_setup.svh
  VCS_MODE_ARGS=(+allmtm +neg_tchk +delay_mode_path +define+GATE_SDF)
fi

{
  printf '+incdir+.\n'
  printf -- '-v %s\n' "$STD_MODEL"
  printf -- '-v %s\n' "$IO_MODEL"
  printf '%s\n' "$PLL_MODEL"
  printf '%s\n' "$NETLIST"
  printf '%s\n' "$SHARED_DIR/uart_host.sv"
  printf '%s\n' "$SHARED_DIR/gate_pipeline_env.sv"
  printf '%s\n' "$SCRIPT_DIR/tb_gate_pipeline_regression.sv"
} > gate_pipeline_regression_filelist.f

echo "Node=$(hostname) Job=$JOB Start=$(date)"
echo "Regression source=$SCRIPT_DIR"
echo "Shared gate environment=$SHARED_DIR"
echo "Tests=${TESTS[*]}"
echo "Mode=$MODE"
echo "Netlist=$NETLIST"
sha256sum "$NETLIST" | tee netlist_sha256.txt
if [ "$MODE" != zero ]; then
  echo "SDF=$SDF"
  sha256sum "$SDF" | tee sdf_sha256.txt
fi
echo "PLL model=$PLL_MODEL"
echo "PLL config=0x$PLL_CFG_HEX"
echo "Standard-cell model=$STD_MODEL"

vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    "${VCS_MODE_ARGS[@]}" \
    -f gate_pipeline_regression_filelist.f \
    -top tb_gate_pipeline_regression \
    -o ./simv_gate_pipeline_regression \
    -l compile_gate_pipeline_regression.log

for test_case in "${TESTS[@]}"; do
  log="sim_gate_pipeline_regression_${MODE}_${test_case}.log"
  echo "RUN mode=$MODE test=$test_case Start=$(date)"
  rm -f sdf_annotate.log
  ./simv_gate_pipeline_regression "${SIM_MODE_ARGS[@]}" \
      +TEST="$test_case" +PLL_CFG="$PLL_CFG_HEX" -l "$log"
  if [ "$MODE" != zero ]; then
    grep -q 'Doing SDF annotation .* Done' "$log"
    if [ -s sdf_annotate.log ]; then
      cp sdf_annotate.log "sdf_annotate_${test_case}.log"
    else
      grep -E 'SDF|annotation|MTM' "$log" \
          > "sdf_annotate_${test_case}.log" || true
    fi
  fi
  marker="[TB_GATE_PIPELINE_REGRESSION_${test_case^^}] PASS"
  grep -Fq "$marker" "$log"
  echo "PASS mode=$MODE test=$test_case log=$WORK/$log End=$(date)"
done

printf 'PASS mode=%s tests=%s\n' "$MODE" "${TESTS[*]}" \
    > REGRESSION_SUITE_PASS.txt
echo "REGRESSION SUITE PASS: $WORK/REGRESSION_SUITE_PASS.txt"
