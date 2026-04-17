#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$SCRIPT_DIR/sim_build_vcs_tpu_ctrl_dma_integration"
RTL_DIR="$SOC_DIR/rtl"
VERILOG_AXI_DIR="/home/jjt/soc/my_soc/verilog-axi/rtl"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

export VCS_ARCH_OVERRIDE=linux

vlogan -full64 -sverilog \
  "$RTL_DIR/tpu_ctrl_axil_regs.v" \
  "$RTL_DIR/tpu_mlp_compute_stub.v" \
  "$RTL_DIR/tpu_desc_fetch_dma_stub.v" \
  "$RTL_DIR/panda_soc_shared_mem_subsys.v" \
  "$VERILOG_AXI_DIR/priority_encoder.v" \
  "$VERILOG_AXI_DIR/arbiter.v" \
  "$VERILOG_AXI_DIR/axi_interconnect.v" \
  "$VERILOG_AXI_DIR/axi_ram.v" \
  "$SCRIPT_DIR/tb_tpu_ctrl_dma_integration.sv"

vcs -full64 tb_tpu_ctrl_dma_integration -o simv_tpu_ctrl_dma_integration
./simv_tpu_ctrl_dma_integration
