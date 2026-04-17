#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOC_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$SOC_DIR/sim_build_vcs_desc_dma_tb"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

export VCS_ARCH_OVERRIDE=linux

vlogan -full64 -sverilog \
  /home/jjt/soc/my_soc/verilog-axi/rtl/priority_encoder.v \
  /home/jjt/soc/my_soc/verilog-axi/rtl/arbiter.v \
  /home/jjt/soc/my_soc/verilog-axi/rtl/axi_interconnect.v \
  /home/jjt/soc/my_soc/verilog-axi/rtl/axi_ram.v \
  "$SOC_DIR/rtl/panda_soc_shared_mem_subsys.v" \
  "$SOC_DIR/rtl/tpu_mlp_compute_stub.v" \
  "$SOC_DIR/rtl/tpu_desc_fetch_dma_stub.v" \
  "$SOC_DIR/tb/tb_tpu_desc_fetch_dma_stub.sv"

vcs -full64 tb_tpu_desc_fetch_dma_stub -o simv
./simv
