# Competition Stage Partition Plan

## Current 600 Structure

The current `600_panda_risc_v` organization is functionally close to three macro stages:

- `IFU`
- `DCD / Dispatch`
- `EXU`

Observed from the current top-level wiring:

- `panda_risc_v_ifu` outputs fetched instruction payload plus predecode metadata
- `panda_risc_v_dcd_dsptc` reads the register file, decodes, and directly dispatches requests to multiple execution units
- `panda_risc_v_exu` contains ALU / LSU / CSR / MUL / DIV / commit-side behavior

This means the first real refactor target is not the whole SoC shell.
It is the interface style between decode/dispatch and execution.

## Target 5-Stage Split

The competition core should be reshaped into:

- `IF`
- `ID`
- `EX`
- `MEM`
- `WB`

### IF

Responsibilities:

- PC selection
- fetch request generation
- predictor lookup
- small fetch / prefetch buffer
- branch redirect acceptance

Keep from current 600 IFU:

- instruction bus control path
- predecode support where it is still useful
- PC update foundation

Move out of IF emphasis:

- anything that makes the IFU too tightly dependent on later execution bookkeeping

### ID

Responsibilities:

- full decode
- register file read
- immediate generation
- hazard detection
- bypass selection logic input generation
- formation of a single decoded micro-op payload

Keep from current `dcd_dsptc`:

- decoder logic
- register-file read path
- basic hazard-related awareness

Change fundamentally:

- stop directly dispatching separate requests to ALU / LSU / CSR / MUL / DIV from ID
- replace that direct fanout with one main `ID/EX` payload

### EX

Responsibilities:

- ALU execute
- branch compare and redirect generation
- effective address generation
- multiply / divide start or progress control
- CSR operation preparation

Main rule:

- EX should consume one decoded operation stream
- EX decides whether the instruction completes in EX or flows into MEM / WB handling

### MEM

Responsibilities:

- load / store sequencing
- load data formatting
- simple store buffering if retained
- memory exception completion

Main rule:

- keep LSU in-order and competition-friendly
- do not import 601-style heavy buffering structures

### WB

Responsibilities:

- register writeback
- CSR writeback
- precise retirement point
- exception / interrupt finalization point

Main rule:

- create a single visible architectural completion stage for report clarity

## First Interface Cuts

### Cut 1: IFU output becomes explicit IF/ID payload

Current output group:

- `m_if_res_data`
- `m_if_res_msg`
- `m_if_res_id`
- `m_if_res_is_first_inst_after_rst`
- `m_if_res_valid/ready`

Action:

- preserve these semantics initially
- reinterpret them as the first visible `IF/ID` boundary
- keep this as the least risky first step

### Cut 2: Replace direct multi-unit dispatch with one decode payload

Current `dcd_dsptc` emits many parallel request channels:

- ALU request
- LSU request
- CSR request
- MUL request
- DIV request

Action:

- define a unified decoded instruction payload at the `ID/EX` boundary
- move detailed unit selection downstream

Why this matters:

- it is the cleanest way to turn the current 3-block structure into a reportable 5-stage pipeline
- it reduces top-level wiring explosion
- it creates a clean place to insert bypass / interlock / predictor recovery control

### Cut 3: Split EXU into EX-side control and MEM/WB-side completion

Current `panda_risc_v_exu` is too broad.
It mixes:

- ALU execution
- LSU interaction
- CSR handling
- multiply/divide execution
- retirement-side effects
- flush generation
- debug/trap handling

Action:

- first keep the legacy submodules internally if needed
- but create visible stage boundaries above them:
  - execute-side decision logic
  - memory completion path
  - writeback / commit point

## Priority Files For The First RTL Cut

Primary files:

- `rtl/panda_risc_v.v`
- `rtl/ifu/panda_risc_v_ifu.v`
- `rtl/decoder_dispatcher/panda_risc_v_dcd_dsptc.v`
- `rtl/exu/panda_risc_v_exu.v`

Secondary files likely to follow:

- `rtl/exu/panda_risc_v_lsu.v`
- `rtl/decoder_dispatcher/panda_risc_v_reg_file_rd.v`
- core-facing testbenches under `tb/tb_panda_risc_v*`

## First Implementation Sequence

1. keep the SoC shell unchanged
2. preserve the current fetch result bundle as the temporary `IF/ID` register payload
3. redefine decode output as a single `ID/EX` operation payload
4. split EXU behavior into visible `EX -> MEM -> WB` control boundaries
5. only after that, tighten bypass and branch-predict recovery details

## Engineering Constraint

If a refactor step does not make the stage boundaries more visible or make the judged build smaller / safer, it should not be part of the first implementation cut.


## Implemented So Far

Current explicit stage cuts already added in RTL:

- `IF -> ID` now passes through `panda_risc_v_if_id_pipe`
- `ID -> EX` now passes through `panda_risc_v_id_ex_pipe`

This means the next architectural cleanup target should move deeper into the core:

- make the EXU boundary more visibly split toward `EX / MEM / WB`
- simplify LSU completion and writeback visibility


### Newly Landed Boundary Note

After the earlier `IF -> ID` and `ID -> EX` cuts, the next visible cleanup has now also landed inside EXU:

- `completion sources -> WB` now passes through `panda_risc_v_wb_pipe`
- the writeback / retirement entrance is therefore explicitly registered in RTL

This means the remaining major ambiguity is no longer the `WB` entrance itself, but the still-mixed `EX / MEM` responsibility around LSU request / response handling.


### Newly Landed Boundary Note 2

The LSU request side is now also explicitly staged:

- `EX -> MEM` on the LSU request path now passes through `panda_risc_v_ex_mem_pipe`
- together with `completion sources -> WB` through `panda_risc_v_wb_pipe`, the back half of the pipeline now has a visible memory-entry boundary and a visible writeback-entry boundary

The main remaining cleanup target is no longer whether a MEM boundary exists at all, but how cleanly LSU completion, exception visibility, and later bypass / interlock behavior are expressed around that boundary.


### Newly Landed Boundary Note 3

The EXU-exported `lsu_idle` semantic is now intentionally stronger than the raw LSU-core idle signal.

For barrier instructions, the system now treats the memory path as idle only when all three regions are empty:

- no older LSU request is still in current `EX`
- no older LSU request is buffered in `panda_risc_v_ex_mem_pipe`
- `panda_risc_v_lsu` itself is idle

This matters because after the explicit `EX/MEM` cut, using only the raw LSU-core idle signal allowed `fence_i` to overtake older stores that had not yet entered LSU. The new definition restores correct ordering while preserving the explicit stage boundary.
