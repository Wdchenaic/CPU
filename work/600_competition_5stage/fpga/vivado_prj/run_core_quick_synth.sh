#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
PART=${1:-xc7z020clg400-1}
TOP=${2:-panda_risc_v}
vivado -mode batch -source "$SCRIPT_DIR/scripts/run_core_quick_synth.tcl" -tclargs "$PART" "$TOP"
