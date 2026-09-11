#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH -J pbit_gate_pll_bp
#SBATCH -o gate-pll-bypass-%j.out
#SBATCH -e gate-pll-bypass-%j.err

set -eo pipefail
set +u
source ~/.bashrc
set -u

ROOT="${PROJECT_PATH:-${SLURM_SUBMIT_DIR:-$PWD}}"
PLL_MODEL_KIND="${PLL_MODEL_KIND:-vendor}"
PLL_CFG_HEX="${PLL_CFG_HEX:-021c}"
DEFAULT_DC_RUN="/public3/home/t6s011227/dc_pbit_chimera_16_20_32_40_200_250_300_350MHz_ss125_fanout32/dc_result/pbit_io_wrapper_chimera_cf76b05_20x20_3200pbit_350MHz_ss_v1p08_125c_fanout32_fixed_area/36276892_20x20_3200pbit_350MHz"
DC_RUN="${DC_RUN:-$DEFAULT_DC_RUN}"
NETLIST="${NETLIST:-}"
IO_MODEL="${IO_MODEL:-/public3/home/t6s011227/ICsprout_55LLULP1225_IO_0901/ICsprout_55LLULP1225_IO_0901/IC055L_GPIO3P3V_CDG_v1.1a/verilog/ic055l_gpio3p3v_cdg_v1p1a/IC055L_GPIO3P3V_CDG.v}"
STD_MODEL_DIR="${STD_MODEL_DIR:-/public3/home/t6s011227/ICsprout_55LLULP1225_STD_0818/ICsprout55_SC9T_BASIC_SVT/0.1/verilog}"
STD_MODEL="${STD_MODEL:-$STD_MODEL_DIR/ICsprout55_9TSVT_basic.v}"

case "$PLL_MODEL_KIND" in
  vendor)
    PLL_MODEL="${PLL_MODEL:-/public3/home/t6s011227/ip_MPW_55/verilog/PLL_TOP.v}"
    ;;
  ideal)
    PLL_MODEL="${PLL_MODEL:-$ROOT/pll_functional_model.sv}"
    ;;
  *)
    echo "PLL_MODEL_KIND must be vendor or ideal" >&2
    exit 2
    ;;
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

test -r "$NETLIST"
test -r "$PLL_MODEL"
test -r "$IO_MODEL"
test -r "$STD_MODEL"
test -r "$ROOT/uart_host.sv"
test -r "$ROOT/tb_gate_pll_bypass.sv"

if [[ "$(basename "$STD_MODEL")" == *_pg.v ]]; then
  echo "Use the non-PG standard-cell model with the non-PG netlist: $STD_MODEL" >&2
  exit 2
fi
if grep -Eq 'module[[:space:]]+DFFRNQX0P5_9TSVT[[:space:]]*\([^;]*(VDD|VSS|VNW|VPW)' "$STD_MODEL"; then
  echo "Selected standard-cell model exposes PG pins: $STD_MODEL" >&2
  exit 2
fi
if grep -Eq '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST"; then
  echo "Unmapped generic cells remain in gate netlist: $NETLIST" >&2
  exit 2
fi
if ! grep -q 'PLL_TOP' "$NETLIST"; then
  echo "PLL_TOP macro instance not found in gate netlist: $NETLIST" >&2
  exit 2
fi

JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$ROOT/sim_runs/gate_pll_bypass_${PLL_MODEL_KIND}_${JOB}"
mkdir -p "$WORK"
cd "$WORK"

{
  printf -- '-v %s\n' "$STD_MODEL"
  printf -- '-v %s\n' "$IO_MODEL"
  printf '%s\n' "$PLL_MODEL"
  printf '%s\n' "$NETLIST"
  printf '%s\n' "$ROOT/uart_host.sv"
  printf '%s\n' "$ROOT/tb_gate_pll_bypass.sv"
} > gate_pll_bypass_filelist.f

echo "Node: $(hostname) Start: $(date)"
echo "Netlist: $NETLIST"
echo "PLL model kind: $PLL_MODEL_KIND"
echo "PLL model: $PLL_MODEL"
echo "Mode: zero-delay standard cells"

vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    +notimingcheck +delay_mode_zero +define+functional \
    -f gate_pll_bypass_filelist.f -top tb_gate_pll_bypass \
    -o ./simv -l compile_gate_pll_bypass.log

./simv +PLL_CFG="$PLL_CFG_HEX" -l sim_gate_pll_bypass_zero.log

grep -q '^\[TB_GATE_PLL_BYPASS\] PASS' sim_gate_pll_bypass_zero.log
echo "PASS: $WORK/sim_gate_pll_bypass_zero.log End: $(date)"
