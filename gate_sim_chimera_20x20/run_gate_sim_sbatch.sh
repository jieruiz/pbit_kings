#!/bin/bash
#SBATCH -p v6_384
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH -J pbit_gate_sim
#SBATCH -o gate-sim-%j.out
#SBATCH -e gate-sim-%j.err

set -eo pipefail
set +u
source ~/.bashrc
set -u

ROOT="${PROJECT_PATH:-${SLURM_SUBMIT_DIR:-$PWD}}"
MODE="${MODE:-zero}"
PLL_CFG_HEX="${PLL_CFG_HEX:-021c}"
DEFAULT_DC_RUN="/public3/home/t6s011227/dc_pbit_chimera_16_20_32_40_200_250_300_350MHz_ss125_fanout32/dc_result/pbit_io_wrapper_chimera_cf76b05_20x20_3200pbit_350MHz_ss_v1p08_125c_fanout32_fixed_area/36276892_20x20_3200pbit_350MHz"
DC_RUN="${DC_RUN:-$DEFAULT_DC_RUN}"
NETLIST="${NETLIST:-}"
SDF="${SDF:-}"
PLL_MODEL="${PLL_MODEL:-/public3/home/t6s011227/ip_MPW_55/verilog/PLL_TOP.v}"
IO_MODEL="${IO_MODEL:-/public3/home/t6s011227/ICsprout_55LLULP1225_IO_0901/ICsprout_55LLULP1225_IO_0901/IC055L_GPIO3P3V_CDG_v1.1a/verilog/ic055l_gpio3p3v_cdg_v1p1a/IC055L_GPIO3P3V_CDG.v}"
STD_MODEL_DIR="${STD_MODEL_DIR:-/public3/home/t6s011227/ICsprout_55LLULP1225_STD_0818/ICsprout55_SC9T_BASIC_SVT/0.1/verilog}"
STD_MODEL="${STD_MODEL:-$STD_MODEL_DIR/ICsprout55_9TSVT_basic.v}"

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
test -d "$STD_MODEL_DIR"
test -r "$STD_MODEL"

# This runner uses the non-PG gate netlist. Loading basic.v and basic_pg.v
# together defines every cell twice and can make VCS bind the PG definition,
# leaving VDD/VSS/VNW/VPW unconnected and all sequential outputs unknown.
if [[ "$(basename "$STD_MODEL")" == *_pg.v ]]; then
  echo "Non-PG gate simulation requires the non-PG standard-cell model: $STD_MODEL" >&2
  exit 2
fi
if grep -Eq 'module[[:space:]]+DFFRNQX0P5_9TSVT[[:space:]]*\([^;]*(VDD|VSS|VNW|VPW)' "$STD_MODEL"; then
  echo "Selected standard-cell model exposes PG pins but the selected netlist does not: $STD_MODEL" >&2
  exit 2
fi

# A gate simulation cannot validate a netlist that still contains DesignWare/
# generic sequential placeholders. Their undriven outputs propagate X into the
# reset synchronizers and UARTs, which otherwise looks like a protocol timeout.
if grep -Eq '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST"; then
  echo "Unmapped generic cells remain in gate netlist: $NETLIST" >&2
  grep -nE '\\\*\*SEQGEN\*\*|(^|[^[:alnum:]_])GTECH' "$NETLIST" \
      | head -20 >&2
  echo "Use a DC result that passed the post-compile fully-mapped check." >&2
  exit 2
fi

case "$MODE" in
  zero)
    DELAY_OPT=+delay_mode_zero
    MODEL_OPT=+define+functional
    TIMING_CHECK_OPT=+notimingcheck
    ;;
  sdf)
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
    test -r "$SDF"
    DELAY_OPT=+delay_mode_path
    MODEL_OPT=
    TIMING_CHECK_OPT=+neg_tchk
    ;;
  *) echo "MODE must be zero or sdf" >&2; exit 2 ;;
esac

JOB="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)_$$}"
WORK="$ROOT/sim_runs/gate_${MODE}_${JOB}"
mkdir -p "$WORK"
cd "$WORK"

if [ "$MODE" = sdf ]; then
  # VCS 2018 rejects a runtime string as the first $sdf_annotate argument.
  # Generate a per-job literal so the same testbench supports both modes.
  printf 'initial begin\n  $display("[GATE] annotating SDF=%s");\n  $sdf_annotate("%s", dut, , "sdf_annotate.log", "MAXIMUM");\nend\n' \
      "$SDF" "$SDF" > gate_sdf_setup.svh
else
  printf 'initial $display("[GATE] zero-delay mode");\n' > gate_sdf_setup.svh
fi

{
  printf '+incdir+.\n'
  printf -- '-v %s\n' "$STD_MODEL"
  printf -- '-v %s\n' "$IO_MODEL"
  printf '%s\n' "$PLL_MODEL"
  printf '%s\n' "$NETLIST"
  printf '%s\n' "$ROOT/uart_host.sv"
  printf '%s\n' "$ROOT/tb_gate_wrapper.sv"
} > gate_filelist.f

echo "Node: $(hostname) Mode: $MODE Start: $(date)"
echo "Netlist: $NETLIST"
echo "PLL model: $PLL_MODEL"
echo "IO model: $IO_MODEL"
echo "Standard-cell model: $STD_MODEL"
echo "Gate options: $DELAY_OPT $MODEL_OPT $TIMING_CHECK_OPT"

vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
    "$TIMING_CHECK_OPT" "$DELAY_OPT" $MODEL_OPT +define+GATE_INTERNAL_DIAG \
    -f gate_filelist.f -top tb_gate_wrapper \
    -o ./simv -l compile_gate.log

if [ "$MODE" = sdf ]; then
  ./simv +maxdelays +sdfverbose +PLL_CFG="$PLL_CFG_HEX" \
      -l sim_gate_sdf.log
  LOG=sim_gate_sdf.log
  test -s sdf_annotate.log
else
  ./simv +PLL_CFG="$PLL_CFG_HEX" -l sim_gate_zero.log
  LOG=sim_gate_zero.log
fi

grep -q '^\[TB_GATE_WRAPPER\] PASS' "$LOG"
echo "PASS: $WORK/$LOG End: $(date)"
