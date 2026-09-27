#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-sdf}"

case "$MODE" in
  zero|sdf) ;;
  --dry-run) MODE=sdf ;;
  *) echo "Usage: $0 [sdf|zero|--dry-run]" >&2; exit 2 ;;
esac

if [ "${1:-}" = "--dry-run" ]; then
  printf 'sbatch --export=ALL,MODE=%q,LITE_SIM_SOURCE_DIR=%q %q\n' \
      "$MODE" "$SCRIPT_DIR" \
      "$SCRIPT_DIR/run_gate_pipeline_500_maxcut_lite_sbatch.sh"
else
  sbatch --export=ALL,MODE="$MODE",LITE_SIM_SOURCE_DIR="$SCRIPT_DIR" \
      "$SCRIPT_DIR/run_gate_pipeline_500_maxcut_lite_sbatch.sh"
fi
