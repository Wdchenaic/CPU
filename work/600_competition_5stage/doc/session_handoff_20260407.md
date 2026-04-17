# Session Handoff - 2026-04-07

## Session Identity
- Session ID: `019d5dd2-886f-7c52-9b7a-f6d9f3201872`
- Resume command: `codex resume 019d5dd2-886f-7c52-9b7a-f6d9f3201872`
- Workspace: `/mnt/hgfs/wdchenaic/CPU_Copetition`
- Main project: `work/600_competition_5stage`
- Raw session dump: `[my project context.txt](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/doc/my%20project%20context.txt)`

## What Was Done In This Session
- 明确了项目主线先按 `RV32I` 收敛，不先推进 `M` 扩展实现，`M` 留到后面评估面积/性能性价比再决定是否保留。
- 新增并接通了两个异常定向用例：
  - `software/test/illegal_exception_asm/illegal_exception_asm.S`
  - `software/test/load_misalign_exception_asm/load_misalign_exception_asm.S`
- 用本地安装到 `/tmp` 的 RISC-V 工具链生成了对应镜像并接入 VCS 单项回归。
- 先前已确认 `illegal_exception` 能过；后续围绕 `load misalign` 做了多轮 debug。
- 定位到根因是异常 flush 后，faulting `lw x6,2(x0)` 在数据相关性跟踪表里残留，导致 trap handler 中 `bne t0,t1` 对 `rs2=x6` 一直被判定为 RAW，后续 pass/fail 标志写不出去。
- 已修复相关性表在异常 flush 下对这类短指令残留项的清理问题。

## Latest Verified State
- `rv32ui-load_misalign_exception.txt`: PASS
- `rv32ui-illegal_exception.txt`: PASS

## Key Root Cause And Fix
### Root cause
- `load misalign` 进入异常后，faulting `lw` 没有从 `data_dpc_monitor` 的生命周期表里被正确清掉。
- 结果 trap handler 执行到 `bne t0,t1` 时，`raw_check_rs2_id = x6`，而旧的 `lw x6,2(x0)` 仍在依赖表中，`dcd_rs2_raw_dpc` 持续为 1，指令卡死。

### Final effective fix
- 文件：[panda_risc_v_data_dpc_monitor.v](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/rtl/decoder_dispatcher/panda_risc_v_data_dpc_monitor.v)
- 文件：[panda_risc_v.v](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/rtl/panda_risc_v.v)
- 修复点：
  - 补上 `dpc_trace_dsptc_is_long_inst` 到 `data_dpc_monitor` 的顶层连线。
  - 引入并维护 `inst_actual_long_inst`，用“派遣当拍的真实长指令属性”替代 IFQ 初始位，避免 misaligned LS 被错误按 long-inst 生命周期跟踪。
  - 调整 flush 清理优先级，使异常 flush 对“短指令但已推进到 EXU 生命周期”的残留表项也会无条件清除，不再被 `inst_adv_to_exu` 抢优先级留下脏项。

## Files Touched In Or Around This Session
- [panda_risc_v_data_dpc_monitor.v](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/rtl/decoder_dispatcher/panda_risc_v_data_dpc_monitor.v)
- [panda_risc_v.v](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/rtl/panda_risc_v.v)
- [tb_panda_risc_v.sv](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/tb/tb_panda_risc_v/to_compile/tb/tb_panda_risc_v.sv)
- [illegal_exception_asm.S](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/software/test/illegal_exception_asm/illegal_exception_asm.S)
- [load_misalign_exception_asm.S](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/software/test/load_misalign_exception_asm/load_misalign_exception_asm.S)
- [pending_validation_status_20260406.md](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/doc/pending_validation_status_20260406.md)

## Important Current Caveat
- [tb_panda_risc_v.sv](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/tb/tb_panda_risc_v/to_compile/tb/tb_panda_risc_v.sv) 里还保留了大量这轮加的临时 debug print。
- 这些 print 是为了追 `load misalign` 残留依赖问题加的，现在功能点已经过了，下一次会话建议先清理或至少大幅回退这些临时观测，避免污染后续日志。

## Recommended Immediate Next Steps
1. 清理 `tb_panda_risc_v.sv` 里本轮临时 debug 打印，只保留真正有长期价值的最小观测。
2. 重新跑一轮异常相关的小回归，至少覆盖：
   - `rv32ui-illegal_exception.txt`
   - `rv32ui-load_misalign_exception.txt`
3. 更新 [pending_validation_status_20260406.md](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/doc/pending_validation_status_20260406.md)，把最新“两个异常用例均 PASS”的状态写进去。
4. 然后继续原计划的 RV32I 主线验证，不碰 `M`：
   - 下一优先级建议转到其他异常路径或中断路径
   - 再往后是软件 smoke test
   - 性能优化仍然排在“当前主线验证更稳”之后

## Project Strategy To Continue With
- 当前主线：先把 `RV32I` 五级流水做成稳定、能验证、能演示、能交付的版本。
- `M` 扩展：暂不实现/不深挖，只做后续面积性能性价比分析。
- 当前阶段优先级：验证收敛优先于性能优化，性能优化只做小而可控的点。

## If You Reopen On Another Account
- 先打开这个目录：`/mnt/hgfs/wdchenaic/CPU_Copetition`
- 先读这两个文件：
  - `[session_handoff_20260407.md](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/doc/session_handoff_20260407.md)`
  - `[my project context.txt](/mnt/hgfs/wdchenaic/CPU_Copetition/work/600_competition_5stage/doc/my%20project%20context.txt)`
- 如果新环境也有 Codex CLI，可尝试：`codex resume 019d5dd2-886f-7c52-9b7a-f6d9f3201872`
- 如果不 resume，就把这份 md 直接贴给新会话，基本可以无缝接上。
