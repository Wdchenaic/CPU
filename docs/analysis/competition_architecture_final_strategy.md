# Competition Architecture Final Strategy

## Context

This note consolidates the final architecture direction for the 2026 七星微 CPU competition project after comparing:

- `600_panda_risc_v`
- `601_panda_risc_v_2`
- `VexRiscv`
- `biRISC-V`
- the local competition requirements in `赛题要求.txt`

## Final Decision

Use a `600++` strategy, not a `601--` strategy.

That means:

- Use `600_panda_risc_v` as the engineering base
- Build a clearly explainable `5-stage`, `single-issue`, `in-order` competition CPU
- Borrow `hazard / bypass / branch prediction` architecture mainly from `VexRiscv`
- Borrow only small front-end implementation details from `601_panda_risc_v_2`
- Borrow parameterization methodology from `biRISC-V`

## Why This Direction

### Competition compliance

The competition wording explicitly asks for:

- a `5-stage pipeline`
- hazard handling
- at least `2` performance optimizations
- complete Verilog/VHDL implementation, verification, FPGA validation, and application demo

This makes a clearly presented `IF / ID / EX / MEM / WB` design the safest mainline.

### Why not use 601 as the main line

`601` is powerful, but it is too heavy for the competition main submission:

- `6-stage`
- out-of-order issue
- ROB-based register renaming
- much heavier LSU

Measured local complexity indicators:

- `600` main core path RTL: about `9415` lines
- `601` `core_rtl`: about `19687` lines
- `601 LSU`: `2312` lines
- `600 LSU`: `532` lines
- `601 LSU + IQ + ROB`: `4780` lines, about `24.3%` of the 601 core RTL

Conclusion:

- `601` is valuable as a performance feature donor
- `601` is not a good competition submission base

### Why not use VexRiscv as the base

`VexRiscv` is the best architecture donor, but not the best engineering base here.

Strengths:

- already a `5-stage` in-order style reference
- mature hazard / branch handling
- has public FPGA LUT and CoreMark data

Problem:

- it is written in `SpinalHDL`
- this project is currently built around a Verilog Panda SoC flow

If used as the base, the work changes from "upgrade a CPU in an existing project" to "rebuild the project stack around a different hardware-generation flow".

### Why not use biRISC-V as the base

`biRISC-V` is even less suitable as the base because its mainline architecture is farther from the competition story:

- dual-issue
- `6/7-stage`
- higher-performance in-order core

It is useful for ideas, but not as the submission mother project.

## Why 600 is the base

`600` is not the strongest core, but it is the best engineering base.

It already includes:

- SoC integration path
- software flow
- FPGA projects
- debug path
- testbench structure
- lightweight default system options

Local project-scale evidence:

- `software`: `264` files
- `fpga`: `86` files
- `tb`: `353` files

The key benefit is not that nothing else changes after the core upgrade.
The key benefit is that the upgrade can focus on the CPU core, while keeping most of the software, system, FPGA, and bring-up shell.

## Target Competition Core

The target CPU should be:

- `5-stage`
- `single-issue`
- `in-order`
- `RV32I` or `RV32IM`
- full bypass
- small dynamic branch predictor
- simple in-order LSU
- no ROB
- no issue queue
- no out-of-order issue

Pipeline split:

- `IF`: PC, fetch, small prefetch buffer, small predictor
- `ID`: decode, register read, hazard detection, immediate generation
- `EX`: ALU, branch resolve, address generation, mul/div start, CSR op preparation
- `MEM`: simplified in-order LSU
- `WB`: register / CSR writeback and precise retirement point

## Two Mandatory Performance Features

The safest and highest-value competition-visible optimizations are:

1. full bypass plus interlock
2. branch prediction or instruction prefetch

These directly match the competition wording and are easy to explain in the report and defense.

## What To Borrow

### From 600 Panda

- project base
- SoC shell
- memory map
- software flow
- FPGA flow
- system and peripheral infrastructure

### From VexRiscv

- 5-stage organization mindset
- clean hazard / bypass structure
- front-end branch prediction organization
- performance versus LUT tradeoff benchmark

### From 601 Panda

- only small front-end implementation details
- selected branch predictor implementation ideas
- selected bus/front-end handling details

### From biRISC-V

Borrow parameterization style, not the dual-issue architecture.

Most useful parameterization ideas:

- enable / disable branch prediction
- enable / disable load bypass
- enable / disable mul bypass
- predictor resource sizing
- FPGA-optimized register file option
- separate minimal-area and higher-performance configurations

This matches the competition requirement for parameterized and extensible design.

## What Not To Borrow

Do not use the following as the competition mainline:

- ROB
- issue queue
- out-of-order issue
- dual-issue
- heavy 601 LSU structure
- DDR/MIG-based heavy SoC path
- complex cache as a first submission dependency

## Recommended Parameter Set

Suggested competition-core parameters:

- `EN_BRANCH_PRED`
- `BTB_ENTRY_N`
- `BHT_ENTRY_N`
- `RAS_ENTRY_N`
- `EN_LOAD_BYPASS`
- `EN_MUL_BYPASS`
- `EN_FULL_BYPASS`
- `LOAD_USE_INTERLOCK`
- `STORE_BUF_DEPTH`
- `PREFETCH_DEPTH`
- `EN_DCACHE`
- `DEBUG_SUPPORTED`
- `REGFILE_FPGA_OPT`
- `ITCM_SIZE`
- `DTCM_SIZE`

## Two Build Targets

### Submission build

Goal:

- safe competition delivery
- stable FPGA demo
- better chance to stay under `<5K LUT`

Recommended traits:

- branch prediction on
- full bypass on
- small predictor tables
- dcache off
- debug off
- lightweight system

### Debug / perf build

Goal:

- development convenience
- waveform/debug support
- benchmarking convenience

Recommended traits:

- branch prediction on
- full bypass on
- debug on
- slightly larger predictor

## Expected Change Scope on 600

Heavy changes:

- `rtl/ifu`
- `rtl/decoder_dispatcher`
- `rtl/exu`
- `rtl/panda_risc_v.v`

Medium changes:

- core-related testbenches

Mostly retained:

- `software`
- `fpga`
- `rtl/system`
- `rtl/peripherals`
- most memory-map and bring-up structure

So the project is not "unchanged outside the core".
The point is that it remains a controlled core-centric refactor, instead of a whole-project rebuild.

## Execution Order

1. create a competition branch under `work/`
2. reshape the 600 core into a visible `IF / ID / EX / MEM / WB`
3. add full bypass and load-use interlock
4. add a small predictor or prefetch mechanism
5. run functional tests and custom tests
6. run CoreMark
7. synthesize and track LUT usage
8. finalize design report, verification report, FPGA guide, and defense materials

## Final Summary

The final project direction is:

`600 base` + `5-stage single-issue in-order core` + `VexRiscv-style hazard/branch architecture` + `small 601 front-end details` + `biRISC-V-style parameter knobs`

This is the best balance across:

- competition compliance
- engineering completeness
- area control
- performance-per-complexity
- verification cost
- report and defense clarity
