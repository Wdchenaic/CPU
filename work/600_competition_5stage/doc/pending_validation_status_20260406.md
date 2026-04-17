# Pending Validation Status 2026-04-06

## Current conclusion

- `rv32ui` base regression remains passed.
- Minimal assembly `illegal instruction` exception test passes.
- Minimal assembly `load address misalign` exception test now also passes.
- The current `RV32I` synchronous exception mainline is no longer blocked on the directed exception smoke tests added in this round.

## What was done in this round

- Added directed exception tests under:
  - `software/test/illegal_exception`
  - `software/test/load_misalign_exception`
- Confirmed the C runtime based tests are not suitable for the current `rv32ui` testbench pass/fail convention, so switched to minimal assembly tests:
  - `software/test/illegal_exception_asm/illegal_exception_asm.S`
  - `software/test/load_misalign_exception_asm/load_misalign_exception_asm.S`
- Added temporary timeout debug prints in `tb/tb_panda_risc_v/to_compile/tb/tb_panda_risc_v.sv` to observe:
  - `x3/x26/x27`
  - `s_pst_valid`
  - `s_pst_err_code`
  - `s_pst_pc`
  - `itr_expt_enter`
  - `itr_expt_cause`
  - `flush_req`
  - `flush_addr`
  - writeback-side valid/ready state for ALU/CSR/LSU/MUL/DIV paths

## Verified results

### 1. Illegal instruction exception

- Test image: `tb/tb_panda_risc_v/inst_test/rv32ui-illegal_exception.txt`
- Result: PASS
- Conclusion:
  - `mtvec` redirection works
  - illegal-instruction detection works
  - synchronous trap entry can reach handler and finish through the testbench convention

### 2. Load misaligned exception

- Test image: `tb/tb_panda_risc_v/inst_test/rv32ui-load_misalign_exception.txt`
- Result: PASS
- Root cause summary:
  - the first failure was not a pure decode-side misalignment issue
  - a canceled post-stage result could still create a bogus ALU/CSR writeback dependency and deadlock WB
  - after gating that path, WB was still incorrectly forcing a non-committing post-stage result to wait for grant
- Fixes applied:
  - `rtl/exu/panda_risc_v_exu.v`
    - gate `s_alu_csr_wbk_valid` with `m_pst_need_imdt_wbk`
  - `rtl/exu/panda_risc_v_wb_pipe.v`
    - make the internal WB-pipe valid bits drain atomically as one bundle
  - `rtl/exu/panda_risc_v_wbk.v`
    - only require post-stage grant when the result both commits and needs immediate writeback
- Conclusion:
  - load-misaligned exception can now reach architectural trap handling correctly
  - the directed exception smoke path for current `RV32I` is unblocked

## Recommended next step

- Continue `RV32I` validation with the next priority item after synchronous exceptions:
  - interrupt path smoke test, or
  - a longer software smoke test if interrupt stimulus is not ready yet
- In parallel, the lowest-risk performance optimization candidate remains the IFU fetch-result queue:
  - `rtl/ifu/panda_risc_v_imem_access_ctrler.v`
  - current implementation explicitly notes that when the fetch-result buffer is empty, responses are not bypassed directly, which adds an extra cycle of latency
