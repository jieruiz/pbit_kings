#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -J pbit_g500_sdf
#SBATCH -o gate500-sdf-%j.out
#SBATCH -e gate500-sdf-%j.err

set -eo pipefail
set +u
source ~/.bashrc
set -u

# Slurm executes a copy under /var/spool/slurmd. Prefer the source directory
# exported by the submit helper, then support direct sbatch from this folder.
if [ -n "${GATE_SIM_SOURCE_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$GATE_SIM_SOURCE_DIR" && pwd)"
elif [ -n "${SLURM_SUBMIT_DIR:-}" ] && \
     [ -r "$SLURM_SUBMIT_DIR/uart_host.sv" ]; then
  SCRIPT_DIR="$(cd "$SLURM_SUBMIT_DIR" && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

ROOT="${GATE_SIM_ROOT:-$SCRIPT_DIR}"
TEST="${TEST:-all}"
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
  all) TESTS=(basic small large) ;;
  basic|small|large) TESTS=("$TEST") ;;
  *) echo "TEST must be all, basic, small or large" >&2; exit 2 ;;
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
if [ -z "$SDF" ]; then
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

for file in "$NETLIST" "$SDF" "$PLL_MODEL" "$IO_MODEL" "$STD_MODEL" \
            "$SCRIPT_DIR/uart_host.sv" \
            "$SCRIPT_DIR/gate_pipeline_env.sv" \
            "$SCRIPT_DIR/tb_gate_pipeline_suite.sv"; do
  test -r "$file" || { echo "Required file is not readable: $file" >&2; exit 2; }
done

if [[ "$(basename "$STD_MODEL")" == *_pg.v ]]; then
  echo "The non-PG gate netlist requires a non-PG standard-cell model" >&2
  exit 2
fi
if grep -Eq 'module[[:space:]]+DFFRNQX0P5_9TSVT[[:space:]]*\([^;]*(VDD|VSS|VNW|VPW)' "$STD_MODEL"; then
  echo "Selected standard-cell model exposes PG pins: $STD_MODEL" >&2
  exit 2
fi
if grep -Eq '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST"; then
  echo "Unmapped generic cells remain in gate netlist: $NETLIST" >&2
  grep -nE '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST" | head -20 >&2
  exit 2
fi
if ! grep -Eq '^module[[:space:]]+pbit_io_wrapper([[:space:]]|\()' "$NETLIST"; then
  echo "Top module pbit_io_wrapper is missing from $NETLIST" >&2
  exit 2
fi

JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$ROOT/sim_runs/gate_pipeline_500_sdf_${TEST}_${JOB}"
mkdir -p "$WORK"
cd "$WORK"

# The path comes from find or an explicit trusted environment override and is
# embedded as a literal because this VCS version rejects a runtime SDF string.
if [[ "$SDF" == *'"'* || "$SDF" == *'\\'* ]]; then
  echo "SDF path contains an unsupported quote or backslash: $SDF" >&2
  exit 2
fi
printf 'initial begin\n  $display("[GATE_SDF] annotating MAXIMUM delays: %s");\n  $sdf_annotate("%s", env.dut, , "sdf_annotate.log", "MAXIMUM");\nend\n' \
    "$SDF" "$SDF" > gate_sdf_setup.svh

{
  printf '+incdir+.\n'
  printf -- '-v %s\n' "$STD_MODEL"
  printf -- '-v %s\n' "$IO_MODEL"
  printf '%s\n' "$PLL_MODEL"
  printf '%s\n' "$NETLIST"
  printf '%s\n' "$SCRIPT_DIR/uart_host.sv"
  printf '%s\n' "$SCRIPT_DIR/gate_pipeline_env.sv"
  printf '%s\n' "$SCRIPT_DIR/tb_gate_pipeline_suite.sv"
} > gate_pipeline_sdf_filelist.f

echo "Node=$(hostname) Job=$JOB Start=$(date)"
echo "Gate simulation source=$SCRIPT_DIR"
echo "Tests=${TESTS[*]}"
echo "Netlist=$NETLIST"
sha256sum "$NETLIST" | tee netlist_sha256.txt
echo "SDF=$SDF"
sha256sum "$SDF" | tee sdf_sha256.txt
echo "PLL model=$PLL_MODEL"
echo "PLL config=0x$PLL_CFG_HEX (500MHz: N=40, OD=1)"
echo "Standard-cell model=$STD_MODEL"
echo "Mode=SDF MAXIMUM, path delays and timing checks enabled"

vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    +allmtm +neg_tchk +delay_mode_path +define+GATE_SDF \
    -f gate_pipeline_sdf_filelist.f -top tb_gate_pipeline_suite \
    -o ./simv_gate_pipeline_sdf -l compile_gate_pipeline_sdf.log

for test_case in "${TESTS[@]}"; do
  log="sim_gate_pipeline_sdf_${test_case}.log"
  echo "RUN SDF test=$test_case Start=$(date)"
  rm -f sdf_annotate.log
  ./simv_gate_pipeline_sdf +maxdelays +sdfverbose \
      +TEST="$test_case" +PLL_CFG="$PLL_CFG_HEX" -l "$log"
  # Some VCS 2018 builds print annotation diagnostics only into the simulator
  # transcript even when the fourth $sdf_annotate argument names a log file.
  # Accept either form, but always require positive annotation completion.
  grep -q 'Doing SDF annotation .* Done' "$log"
  if [ -s sdf_annotate.log ]; then
    cp sdf_annotate.log "sdf_annotate_${test_case}.log"
  else
    grep -E 'SDF|annotation|MTM' "$log" \
        > "sdf_annotate_${test_case}.log" || true
  fi
  grep -q "^\[TB_GATE_PIPELINE_${test_case^^}\] PASS" "$log"
  echo "PASS SDF test=$test_case log=$WORK/$log End=$(date)"
done

printf 'PASS SDF MAXIMUM tests=%s\n' "${TESTS[*]}" > SDF_SUITE_PASS.txt
echo "SDF SUITE PASS: $WORK/SDF_SUITE_PASS.txt"
