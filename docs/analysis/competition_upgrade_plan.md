# CPU Competition Upgrade Plan

## Goal

Build a competition-grade RISC-V CPU project for the 2026 七星微赛题 by using the Panda CPU codebase as the main foundation, while selectively borrowing ideas from stronger open-source CPUs for performance, verification, FPGA bring-up, and documentation.

## Local Repository Layout

- `repos/upstream/Opensoc`
  - Contains both `600_panda_risc_v` and `601_panda_risc_v_2`
- `repos/references/official/VexRiscv`
  - Officially relevant FPGA-friendly RV32 reference
- `repos/references/official/rocket-chip`
  - Officially relevant SoC / cache / debug / bus architecture reference
- `repos/references/perf/biriscv`
  - Practical high-performance Verilog reference for branch prediction, cache, bypass, and issue logic
- `work`
  - Reserved for the competition submission branch and derived work
- `docs/analysis`
  - Analysis, architecture notes, gap reports, and plans
- `docs/submission`
  - Reserved for final design report, verification report, FPGA guide, and slides

## Baseline Decision

### 600 Panda RISC-V

Strengths:

- Has a relatively complete SoC, software, FPGA, debug, and test environment
- Has clear project structure and stronger engineering completeness
- Easier to use as a bring-up and submission support reference

Weaknesses:

- Only 3-stage pipeline
- Static branch prediction
- Lower performance ceiling

### 601 Panda RISC-V v2

Strengths:

- 6-stage pipeline
- Dynamic branch prediction with BHT/PHT/BTB/RAS
- AXI-Lite instruction / data / peripheral buses
- Optional DCache
- Out-of-order issue support
- ROB-based register renaming
- Reported `3.188 CoreMark/MHz`

Weaknesses / Risks:

- The competition requirement explicitly emphasizes a 5-stage pipeline
- 601 is more advanced, but the visible architecture deviates from the stated 5-stage requirement
- Direct submission of 601 as-is creates a compliance risk in judging

## Recommended Strategy

Use a dual-track strategy:

- Main submission track:
  - Build a competition-compliant core around the Panda codebase, with visible alignment to the required 5-stage architecture
- Performance reference track:
  - Use 601 as the main source of advanced mechanisms, test ideas, bus adaptation, and performance tuning references

Practical recommendation:

- Keep `600_panda_risc_v` as the engineering bring-up reference
- Use `601_panda_risc_v_2` as the main performance feature donor
- Do not blindly submit 601 unchanged
- Decide early whether to:
  - A. reshape 601 into a clearly explainable 5-stage submission architecture
  - B. or upgrade 600 toward a 5-stage design while transplanting selected 601 features

Current recommendation:

- Short-term: study 601 first, because it contains the most valuable reusable high-performance mechanisms
- Submission architecture decision should be made after checking how hard it is to map 601 into a 5-stage compliant presentation and implementation

## What To Borrow From Each Reference

### From 601 Panda

- Branch prediction structures: `BTB`, `RAS`, history-based predictor
- Better front-end organization
- AXI-Lite based bus split
- DCache structure
- Better benchmark target and performance mindset

### From 600 Panda

- SoC integration path
- Software compilation flow
- FPGA example project
- Debug / OpenOCD / UART programming workflow
- Existing memory map and peripheral support

### From VexRiscv

- 5-stage performance-oriented FPGA-friendly thinking
- Hazard / bypass options
- Cache integration patterns
- Lightweight SoC examples for FPGA demonstration
- How to present configurable CPU features clearly

### From Rocket Chip

- System architecture references only
- Cache / bus / debug / SoC integration concepts
- Report structure inspiration

### From biRISC-V

- Practical Verilog implementation ideas for:
  - branch predictor parameterization
  - bypass choices
  - cache / TCM organization
  - front-end and execution-path timing tradeoffs

## Competition-Oriented Milestones

1. Baseline audit
   - Confirm ISA coverage, CSR behavior, exception behavior, branch handling, and current FPGA bring-up status
2. Architecture decision
   - Choose the final submission core line: `601 reshaped` or `600 upgraded`
3. Compliance closure
   - Align visible architecture, docs, test coverage, and application demos with the赛题 wording
4. Performance upgrades
   - Keep only high-value, judge-visible features
5. Verification and FPGA stabilization
   - `riscv-tests`, custom tests, CoreMark, board demo, waveforms, logs
6. Submission package
   - Design report, verification report, FPGA guide, source package, demo material

## Immediate Next Steps

1. Read the RTL and docs of `600_panda_risc_v` and `601_panda_risc_v_2`
2. Produce a strict gap table against the赛题
3. Decide whether 601 can be safely packaged as a compliant 5-stage-derived architecture
4. If not, define a 5-stage competition branch and transplant only the strongest 601 features
