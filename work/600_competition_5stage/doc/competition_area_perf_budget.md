# Competition Area And Performance Budget

## Status

This note is a first-pass engineering estimate, not a post-synthesis report.

Current limitation:

- no local `yosys`
- no local `vivado`
- no local `iverilog`

So all numbers below are based on:

- local RTL structure of the derived `600_competition_5stage` tree
- feature-level trimming plan
- local reference numbers from `VexRiscv`
- local published performance number from `601_panda_risc_v_2`

## Reference Anchors

### VexRiscv local published data

From the local `VexRiscv` README:

- `full no cache`: `1418 LUT`, `949 FF`, `2.30 CoreMark/MHz`
- `full`: `1840 LUT`, `1158 FF`, `2.30 CoreMark/MHz`
- `full max perf`: `1935 LUT`, `1216 FF`, `2.57 CoreMark/MHz`

Interpretation:

- a good FPGA-oriented `RV32IM` in-order core can reach around `2.3 ~ 2.6 CoreMark/MHz`
- a clean 5-stage core with branch handling and bypass does not inherently require more than `5K LUT`

### 601 Panda local published data

From the local `601_panda_risc_v_2` README:

- published performance: `3.188 CoreMark/MHz`

Interpretation:

- this is a useful upper reference
- it comes with much higher microarchitectural complexity
- it should not be used as the expected number for the competition 5-stage line

## Structural Weight Of The Derived 600 Tree

Measured on the copied branch under `work/600_competition_5stage`:

- editable core path `ifu + decoder_dispatcher + exu`: `7928` lines
- `cache`: `2576` lines
- `debug`: `2056` lines
- `system + peripherals`: `567` lines
- `generic`: `993` lines
- top-level `panda_risc_v.v`: about `1051` lines

Key observation:

- `cache + debug` together account for `4632` lines of RTL footprint
- this is roughly `30%` of the whole 600 RTL tree
- keeping `DCache` and `Debug` off in the first submission line is therefore the single most important area-control decision

## Planned Competition Core

Target microarchitecture:

- `5-stage`
- `single-issue`
- `in-order`
- `RV32I` or `RV32IM`
- full bypass
- load-use interlock
- small dynamic branch predictor or prefetch
- simplified in-order LSU
- no ROB
- no issue queue
- no out-of-order issue

## Build Profiles

### Submission build

Planned settings:

- `EN_BRANCH_PRED = 1`
- `EN_FULL_BYPASS = 1`
- `EN_LOAD_BYPASS = 1`
- small `BTB/BHT/RAS`
- `EN_DCACHE = 0`
- `DEBUG_SUPPORTED = 0`
- lightweight LSU
- stable memory map and SoC shell

### Debug / perf build

Planned settings:

- `EN_BRANCH_PRED = 1`
- `EN_FULL_BYPASS = 1`
- `EN_LOAD_BYPASS = 1`
- slightly larger predictor
- `DEBUG_SUPPORTED = 1`
- extra observability allowed

## First-Pass LUT Estimate

### Submission build

Estimated total LUT range:

- `3200 ~ 4300 LUT`

Reasoning:

- lower anchor starts from `VexRiscv full no cache = 1418 LUT`
- add cost for Panda-style SoC shell and less aggressively optimized Verilog
- add cost for explicit 5-stage pipeline control and bypass network
- keep `DCache` off
- keep `Debug` off
- keep predictor small

Engineering judgment:

- this configuration is the most likely path to stay under the competition `<5K LUT` line
- if the final implementation remains structurally disciplined, the submission line should be feasible

### Debug / perf build

Estimated total LUT range:

- `3900 ~ 5200 LUT`

Reasoning:

- same core as submission build
- debug logic re-enabled
- predictor tables may be slightly larger
- observability and debug-oriented glue often push the design close to or above the strict submission budget

Engineering judgment:

- useful for development
- not the version to optimize first for the competition scoring resource cap

## First-Pass Performance Estimate

### Design-point clock assumption

Use `100 MHz` as the current planning clock.

Reason:

- the competition scoring wording explicitly uses `100 MHz` as an example reference
- no local synthesis report exists yet, so higher Fmax claims would be premature

### Submission build performance estimate

Estimated performance:

- `2.0 ~ 2.4 CoreMark/MHz`

Interpretation at `100 MHz`:

- about `200 ~ 240 CoreMark` total score at that clock point

Reasoning:

- lower than the `601` upper reference of `3.188 CoreMark/MHz`
- near the `VexRiscv` `2.30 CoreMark/MHz` anchor
- supported by the planned full bypass plus branch prediction combination
- penalized by simpler memory system and a conservative submission-oriented implementation style

### Tuned debug / perf build estimate

Estimated performance:

- `2.2 ~ 2.6 CoreMark/MHz`

Reasoning:

- same 5-stage class as the submission build
- slightly larger predictor and easier debug-driven tuning
- still well below the `601` out-of-order line, which is expected

## Risk Notes

### Risks that can push LUT usage up

- keeping full debug in the judged bitstream
- allowing predictor tables to grow too large
- carrying over heavy LSU buffering behavior
- reintroducing cache work too early
- widening control-path bookkeeping during the 3-stage to 5-stage refactor

### Risks that can push performance down

- over-stalling around load-use hazards
- weak branch recovery timing
- excessive flush cost in the front-end
- multi-cycle operations blocking simple integer flow
- conservative LSU sequencing that hurts common load/store patterns

## Immediate Control Rules

To keep the project inside the area/performance envelope:

1. keep `DCache` off in the first judged build
2. keep `Debug` off in the first judged build
3. keep the branch predictor small and parameterized
4. avoid any ROB / IQ / dual-issue style transplant
5. close the 5-stage core first, then optimize predictor details
6. treat any feature without clear score impact as optional

## What Must Happen Next

1. define the exact competition parameter set in the derived work tree
2. refactor the 600 core into visible `IF / ID / EX / MEM / WB`
3. implement full bypass and load-use interlock first
4. synthesize the submission build as soon as a stable compile path exists
5. replace this estimate with real LUT / FF / BRAM numbers once tool access is available

## Implemented Delta 1: Explicit ID/EX Pipe

Implemented in the derived branch:

- added `rtl/decoder_dispatcher/panda_risc_v_id_ex_pipe.v`
- rewired `rtl/panda_risc_v.v` so `dcd_dsptc` now backpressures against the new ID/EX stage instead of the EXU directly

Estimated incremental cost of this cut:

- about `450 FF` for the carried execution payload
- about `30 ~ 80 LUT` for ready/valid glue and control

Estimated performance effect of this cut alone:

- short-term `CoreMark/MHz`: neutral to slightly negative before hazard/bypass retuning
- medium-term clock potential: slightly better, because decode/dispatch and EXU are no longer hard-coupled in one direct boundary

Engineering interpretation:

- this is a good trade for the competition line
- the added area is small relative to the `<5K LUT` target
- the structural gain is large because it creates a real stage boundary for the later `EX / MEM / WB` cleanup


## Implemented Delta 2: Explicit IF/ID Pipe

Implemented in the derived branch:

- added `rtl/ifu/panda_risc_v_if_id_pipe.v`
- rewired `rtl/panda_risc_v.v` so the IFU result bundle now enters decode through an explicit IF/ID register stage

Estimated incremental cost of this cut:

- about `140 FF` for the fetched-instruction payload and control bits
- about `10 ~ 25 LUT` for ready/valid glue

Estimated performance effect of this cut alone:

- short-term `CoreMark/MHz`: essentially neutral before front-end tuning
- medium-term clock potential: slightly better, because IFU and decode are no longer directly timing-coupled

Engineering interpretation:

- this is another good trade for the competition line
- the added area is very small relative to the `<5K LUT` target
- after this cut, the front half of the planned 5-stage pipeline has explicit registered boundaries in RTL


## Implemented Delta 3: Explicit WB Input Pipe

Implemented in the derived branch:

- added `rtl/exu/panda_risc_v_wb_pipe.v`
- rewired `rtl/exu/panda_risc_v_exu.v` so the completion bundle now enters `panda_risc_v_wbk` through an explicit registered WB-stage input

Estimated incremental cost of this cut:

- about `250 ~ 350 FF` for the buffered WB-source payload and per-source valid state
- about `20 ~ 60 LUT` for ready/valid glue and conservative hold logic

Estimated performance effect of this cut alone:

- short-term `CoreMark/MHz`: neutral to slightly negative before LSU / bypass retuning
- medium-term clock potential: slightly better, because the writeback arbitration point is no longer fed only by a direct multi-source combinational fan-in

Engineering interpretation:

- this is still a good trade for the competition line
- it makes the `WB` stage visible enough for report and defense clarity
- it does not finish the `MEM` boundary cleanup yet, but it removes one major ambiguity at the retirement entrance

Current cumulative structural overhead of the explicit stage cuts already landed:

- about `840 ~ 940 FF`
- about `60 ~ 165 LUT`

Current budget interpretation remains unchanged:

- `submission build`: still expected to fit roughly in `3200 ~ 4300 LUT`
- `debug/perf build`: still expected around `3900 ~ 5200 LUT`, with some risk near or above `5K LUT`


## Implemented Delta 4: Explicit EX/MEM LSU Request Pipe

Implemented in the derived branch:

- added `rtl/exu/panda_risc_v_ex_mem_pipe.v`
- rewired `rtl/exu/panda_risc_v_exu.v` so the LSU request bundle now enters `panda_risc_v_lsu` through an explicit registered EX/MEM stage

Estimated incremental cost of this cut:

- about `80 ~ 120 FF` for the buffered LSU-request payload
- about `8 ~ 20 LUT` for ready/valid glue

Estimated performance effect of this cut alone:

- short-term `CoreMark/MHz`: slightly negative before bypass / hazard retuning, because loads and stores now pay one extra request-side stage before LSU launch
- medium-term clock potential: slightly better, because ALU address generation and LSU launch handshake are no longer kept on one direct boundary

Engineering interpretation:

- this is the most architecture-relevant cut so far in the back half of the core
- it makes the mainline story much closer to a real `IF / ID / EX / MEM / WB`
- some of the short-term IPC loss should be treated as expected until later bypass / interlock cleanup is done

Current cumulative structural overhead of the explicit stage cuts already landed:

- about `920 ~ 1060 FF`
- about `68 ~ 185 LUT`

Current budget interpretation remains unchanged:

- `submission build`: still expected to fit roughly in `3200 ~ 4300 LUT`
- `debug/perf build`: still expected around `3900 ~ 5200 LUT`, with some risk near or above `5K LUT`


## Verification Note 2026-04-05

- Real `VCS` compile/sim is now working when the build output is placed on local disk under `/tmp`; VMware shared folders under `/mnt/hgfs` break the final symlink-heavy link stage.
- The smoke test `rv32ui-p-add` now passes on the current 5-stage branch.
- The root bug was not ALU arithmetic itself but stale dependency tracking after the new `ID/EX` stage was inserted. `panda_risc_v_data_dpc_monitor` previously promoted an instruction into `EXU_STAGE` on dispatch acceptance; after the `ID/EX` pipe was added, that promotion became one stage too early and could leave ghost RAW dependencies.
- The current correctness-first baseline temporarily keeps ALU/CSR decode-side bypass disabled in the dependency monitor. This is acceptable for functional bring-up, but the earlier `submission build` performance estimate assumes that an EX/WB-aware bypass network will be restored.
- Area impact of the dependency-tracking retime is negligible versus the previously documented stage-splitting overhead; this is control bookkeeping, not a meaningful datapath expansion.


### Update: EX/WB-aware bypass restored

- The dependency monitor and register-file read arbiter now distinguish two decode-visible short-result sources: the instruction that is entering `EX` in the current cycle, and an ALU/CSR short instruction waiting in the explicit `WB` stage.
- This fixes the earlier false assumption that any tracked short instruction in `EXU_STAGE` could still be serviced by the live `alu_res/csr_atom_rw_dout` path.
- After the EX/WB-aware bypass refactor, the real `VCS` smoke test `rv32ui-p-add` still passes.
- Area impact of this step should remain small relative to the explicit stage cuts already budgeted: mostly extra compare/control logic and two additional decode-bypass select signals, likely on the order of a few dozen LUTs rather than a new datapath class.
- Performance interpretation improves versus the temporary correctness-first baseline because short ALU/CSR RAW chains no longer need to stall all the way until architectural retirement.


## Verification Update 2026-04-05 Evening

- The focused `fence_i` failure is fixed.
- The full `rv32ui-p-*` batch now passes under `VCS`: `39 passed, 0 failed, total 39`.
- The direct root cause of the `fence_i` bug was not IFU stale-fetch suppression. It was an ordering hole created by the explicit `EX/MEM` stage: the EXU-exported `lsu_idle` only reflected the LSU core and did not include pending LSU requests still in `EX` or already buffered at the `EX/MEM` output.
- Because of that, `fence_i` could overtake older stores and its flush could clear `panda_risc_v_ex_mem_pipe`, dropping architecturally older self-modifying-code stores before they reached IMEM.
- The fix is a very small control-only change in `rtl/exu/panda_risc_v_exu.v`: export `lsu_idle` as `lsu_core_idle & (~s_lsu_valid) & (~s_req_valid)`.

Estimated cost / performance impact of this fix:

- area: negligible to very small, roughly `0 ~ 10 LUT` worth of extra control gating
- FF impact: `0`
- CoreMark/MHz impact: effectively neutral in normal code, because `fence` / `fence_i` are rare; in exchange, ordering correctness is restored for self-modifying-code cases

Current budget interpretation remains unchanged even after this fix:

- `submission build`: still expected around `3200 ~ 4300 LUT`
- `debug/perf build`: still expected around `3900 ~ 5200 LUT`
