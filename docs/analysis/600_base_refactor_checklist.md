# 600 Base Refactor Checklist

## Goal

Use `600_panda_risc_v` as the competition engineering base and refactor only the parts that must change for a compliant and competitive `5-stage` submission.

Core principle:

- keep the project shell
- refactor the CPU core
- minimize system-level churn

## Classification

### Keep

These parts should be kept as much as possible because they are already valuable competition assets.

#### Software

Keep most of:

- `software/boot`
- `software/include`
- `software/lib`
- `software/test`

Reason:

- software mainly depends on ISA, CSR behavior, memory map, and peripheral map
- software does not directly depend on whether the core is 3-stage or 5-stage
- if the upgraded core preserves the external programming model, most software remains reusable

#### System and peripherals

Keep most of:

- `rtl/system`
- `rtl/peripherals`

Reason:

- these are outside the main microarchitecture refactor scope
- they provide the stable SoC shell around the CPU

#### FPGA shell

Keep most of:

- `fpga/panda_soc_eva`
- board-level project structure
- constraints and top-level system flow where possible

Reason:

- if the CPU external interface contract stays stable, FPGA integration changes stay limited

## Light Edit

These parts should be adjusted, but not fundamentally redesigned.

### Top-level system integration

Lightly edit:

- `fpga/panda_soc_eva/rtl/panda_risc_v_min_proc_sys.v`
- top-level parameter wiring
- build-time feature switches

Typical edits:

- switch submission/debug configurations
- keep `EN_DCACHE = 0` in first submission line
- keep memory map stable
- update CPU instance parameters after the core refactor

### Scripts and build glue

Lightly edit:

- `scripts`
- any file lists or build references that assume old core structure

Typical edits:

- update source file lists
- update simulation targets
- add distinct build presets for submission and debug/perf

### Selected verification wrappers

Lightly edit:

- system-level TB wrappers that instantiate the CPU top

Typical edits:

- adapt to new parameter set
- keep existing memory/peripheral models if interfaces remain stable

## Refactor

These are the main work items and should be treated as the project center.

### CPU core RTL

Refactor heavily:

- `rtl/panda_risc_v.v`
- `rtl/ifu`
- `rtl/decoder_dispatcher`
- `rtl/exu`

Target:

- reshape into visible `IF / ID / EX / MEM / WB`
- add full bypass and load-use interlock
- add small branch predictor or prefetch support
- simplify LSU into an in-order competition-friendly version

### Core-facing testbenches

Refactor heavily:

- `tb/tb_panda_risc_v`
- `tb/tb_panda_risc_v_ifu`
- `tb/tb_panda_risc_v_dcd_dsptc`
- `tb/tb_panda_risc_v_lsu`
- other microarchitecture-facing TBs tied to the current 3-stage internals

Reason:

- these TBs are coupled to internal stage partitioning and control timing
- a 3-stage to 5-stage change invalidates many old timing assumptions

## Temporarily Disable Or Defer

These features should not be on the critical path of the first submission version.

### DCache-heavy path

Defer in first submission:

- complex `DCache`
- cache tuning
- high-risk cache/controller integration work

Reason:

- area and verification risk
- not required to demonstrate the main competition architecture

### Debug-heavy path

Defer or disable in submission build:

- full debug support
- nonessential debug logic that increases complexity or area

Reason:

- useful for development
- not required in the smallest competition bitstream

### 601-style heavy performance machinery

Do not transplant into the mainline:

- ROB
- issue queue
- out-of-order issue
- heavy LSU buffering structures

Reason:

- violates the intended simplicity of the competition line
- increases report and defense risk
- threatens resource control

## Recommended Build Split

### Submission build

Purpose:

- judged version
- stable FPGA demonstration
- better chance to fit under the LUT budget

Suggested settings:

- `EN_BRANCH_PRED = 1`
- `EN_FULL_BYPASS = 1`
- `EN_LOAD_BYPASS = 1`
- small `BTB/BHT/RAS`
- `EN_DCACHE = 0`
- `DEBUG_SUPPORTED = 0`
- lightweight LSU

### Debug / perf build

Purpose:

- development and debug
- CoreMark bring-up
- waveform and observability support

Suggested settings:

- `EN_BRANCH_PRED = 1`
- `EN_FULL_BYPASS = 1`
- `EN_LOAD_BYPASS = 1`
- slightly larger predictor
- `DEBUG_SUPPORTED = 1`
- optional extra observability hooks

## Practical Sequence

1. clone the 600 line into `work/` as the competition work area
2. freeze the current SoC shell and memory map
3. refactor the core RTL into a visible 5-stage structure
4. make core-related TBs pass again
5. keep software and FPGA flow running with minimal interface changes
6. add the second optimization feature after the 5-stage core is stable
7. synthesize the submission build first and track LUT use early

## Final Engineering Rule

If a change does not clearly improve one of the following, it should stay out of the first submission version:

- competition compliance
- area safety
- verification completeness
- demo stability
- report clarity
