#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST="${1:-all}"
MODE="${2:-max}"

case "$TEST" in
  all|exact|crossbank|boundaries|recovery) ;;
  *) echo "Usage: $0 [all|exact|crossbank|boundaries|recovery] [zero|max|min]" >&2; exit 2 ;;
esac
case "$MODE" in
  zero|max|min) ;;
  *) echo "Usage: $0 [all|exact|crossbank|boundaries|recovery] [zero|max|min]" >&2; exit 2 ;;
esac

sbatch --export=ALL,TEST="$TEST",MODE="$MODE",GATE_REG_SOURCE_DIR="$SCRIPT_DIR" \
    "$SCRIPT_DIR/run_gate_pipeline_regression_sbatch.sh"
