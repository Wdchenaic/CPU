#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$SOC_DIR/sim_build_vcs_ctrl_tb"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

export VCS_ARCH_OVERRIDE=linux

vlogan -full64 -sverilog \
  "$SOC_DIR/rtl/tpu_ctrl_axil_regs.v" \
  "$SOC_DIR/rtl/tpu_ctrl_task_stub.v" \
  "$SOC_DIR/tb/tb_tpu_ctrl_task_stub.sv"

vcs -full64 tb_tpu_ctrl_task_stub -o simv
./simv
