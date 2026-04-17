# RV32UI Regression Summary 2026-04-05

## Final Result

- runner: `tb/tb_panda_risc_v/test_isa_vcs.py`
- binary: `/tmp/competition_vcs_rv32ui/simv_rv32ui`
- suite: `rv32ui-p-*.txt`
- outcome: `39 passed, 0 failed, total 39`
- note: the VCS build directory must stay on local Linux disk such as `/tmp`; building under `/mnt/hgfs` breaks the final symlink-heavy VCS link step.

## Passed Classes

- integer ALU: `add addi and andi or ori xor xori sub slt slti sltiu sltu sll slli srl srli sra srai`
- upper/jump/branch: `lui auipc jal jalr beq bne blt bltu bge bgeu`
- loads/stores: `lb lbu lh lhu lw sb sh sw`
- ordering / self-modifying-code case: `fence_i`
- simple sanity: `simple`

## Root Causes Fixed In This Round

### 1. Load WAW hazard window after adding `ID/EX`

After the explicit `ID/EX` stage was inserted, the dependency monitor no longer promoted long instructions into the outstanding set at the right point. That left a one-cycle WAW hole where a younger short instruction could slip past an older load writing the same `rd`.

The fix was to retime `panda_risc_v_data_dpc_monitor` so a long instruction becomes outstanding as soon as the dispatch-to-`ID/EX` handoff is accepted, while short instructions still use the true `EX` entry point.

### 2. `fence_i` dropping older stores after adding `EX/MEM`

The explicit `EX/MEM` LSU request stage exposed a second bug. Before the fix, the externally visible `lsu_idle` only reflected `panda_risc_v_lsu` itself and did not include:

- an older load/store still sitting in `EX`
- an older load/store already buffered in `panda_risc_v_ex_mem_pipe`

That let `fence_i` dispatch and later flush while an older store was still upstream of LSU. The flush then cleared `panda_risc_v_ex_mem_pipe`, so the store never reached IMEM. The clearest symptom was that `rv32ui-p-fence_i` failed while IMEM word `0x54` remained the old instruction value.

The fix was to redefine the EXU-exported `lsu_idle` as a full LSU-path-idle condition:

- `lsu_core_idle`
- and no pending LSU request in current `EX`
- and no pending LSU request at the `EX/MEM` output

So the current barrier condition is effectively:

```verilog
lsu_idle = lsu_core_idle & (~s_lsu_valid) & (~s_req_valid);
```

This keeps `fence` / `fence_i` from overtaking older memory operations after the 5-stage refactor.

## Files Touched For The Final Fixes

- `rtl/decoder_dispatcher/panda_risc_v_data_dpc_monitor.v`
- `rtl/exu/panda_risc_v_exu.v`
- `tb/tb_panda_risc_v/test_isa_vcs.py`

## What This Means

- The current 5-stage branch has a clean `rv32ui` integer baseline.
- The biggest correctness risks introduced by the explicit `IF/ID`, `ID/EX`, `EX/MEM`, and `WB` cuts have been exercised at ISA level.
- The next verification priority should move to `rv32um`, exception/interrupt directed tests, and then board-oriented software smoke tests.
