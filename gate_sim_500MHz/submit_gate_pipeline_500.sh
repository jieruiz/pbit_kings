#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST="${1:-all}"

case "$TEST" in
  all|basic|small|large) ;;
  --dry-run) TEST=all ;;
  *) echo "Usage: $0 [all|basic|small|large|--dry-run]" >&2; exit 2 ;;
esac

if [ "${1:-}" = "--dry-run" ]; then
  printf 'sbatch --export=ALL,TEST=%q,GATE_SIM_SOURCE_DIR=%q %q\n' \
      "$TEST" "$SCRIPT_DIR" "$SCRIPT_DIR/run_gate_pipeline_500_sbatch.sh"
else
  sbatch --export=ALL,TEST="$TEST",GATE_SIM_SOURCE_DIR="$SCRIPT_DIR" \
      "$SCRIPT_DIR/run_gate_pipeline_500_sbatch.sh"
fi
