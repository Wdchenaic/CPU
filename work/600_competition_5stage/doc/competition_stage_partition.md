# Five-Stage Pipeline Quick Start

本文只说明当前 `work/600_competition_5stage` 的五级流水线主线，以及它如何从原 `600_panda_risc_v` 的三个宏功能块改出来。

## Current Status

当前 RTL 已经具备可见的 `IF / ID / EX / MEM / WB` 边界：

| 边界 | RTL 文件 | 所在位置 |
| --- | --- | --- |
| `IF -> ID` | `rtl/ifu/panda_risc_v_if_id_pipe.v` | `rtl/panda_risc_v.v` |
| `ID -> EX` | `rtl/decoder_dispatcher/panda_risc_v_id_ex_pipe.v` | `rtl/panda_risc_v.v` |
| `EX -> MEM` | `rtl/exu/panda_risc_v_ex_mem_pipe.v` | `rtl/exu/panda_risc_v_exu.v` |
| `MEM/EX completion -> WB` | `rtl/exu/panda_risc_v_wb_pipe.v` | `rtl/exu/panda_risc_v_exu.v` |

这意味着当前项目不再按原 README 的三个宏阶段来介绍，而是按比赛要求的五级流水线来介绍和答辩。

## Original 600 Macro Blocks

原 `600_panda_risc_v` 的组织方式功能上更接近三个大块：

- `panda_risc_v_ifu`：取指、预译码、PC 更新、分支预测基础
- `panda_risc_v_dcd_dsptc`：译码、读寄存器、相关性检查、直接生成多个执行单元请求
- `panda_risc_v_exu`：ALU、LSU、CSR、MUL/DIV、异常、提交、写回混在一个后端大模块中

这种结构可以运行，但对比赛文档和答辩不够清楚，因为 MEM 和 WB 的边界不明显，译码到执行之间也缺少独立的流水级说明。

## Current Five Stages

### IF

职责：

- PC 选择
- 取指请求
- 预译码
- 静态分支预测基础
- 接收 flush/redirect

对应核心文件：

- `rtl/ifu/panda_risc_v_ifu.v`
- `rtl/ifu/panda_risc_v_pc_gen.v`
- `rtl/ifu/panda_risc_v_ibus_ctrler.v`
- `rtl/ifu/panda_risc_v_pre_decoder.v`

### ID

职责：

- 完整译码
- 通用寄存器堆读
- RAW/WAW 相关性检查
- 形成 ALU/LSU/CSR/MUL/DIV 执行请求

对应核心文件：

- `rtl/decoder_dispatcher/panda_risc_v_dcd_dsptc.v`
- `rtl/decoder_dispatcher/panda_risc_v_decoder.v`
- `rtl/decoder_dispatcher/panda_risc_v_reg_file_rd.v`
- `rtl/decoder_dispatcher/panda_risc_v_data_dpc_monitor.v`

### EX

职责：

- ALU 执行
- CSR 原子读写执行
- 分支确认和 flush 生成
- load/store 地址生成
- 乘除法请求发起

对应核心文件：

- `rtl/exu/panda_risc_v_exu.v`
- `rtl/exu/panda_risc_v_alu.v`
- `rtl/exu/panda_risc_v_csr_rw.v`
- `rtl/exu/panda_risc_v_multiplier.v`
- `rtl/exu/panda_risc_v_divider.v`

### MEM

职责：

- LSU 请求排队和发起
- load/store 数据访问
- load 数据返回
- 访存异常生成

对应核心文件：

- `rtl/exu/panda_risc_v_ex_mem_pipe.v`
- `rtl/exu/panda_risc_v_lsu.v`

### WB

职责：

- 汇合 ALU/CSR/LSU/MUL/DIV 写回源
- 写通用寄存器堆
- 退休/提交
- 异常和调试相关完成路径

对应核心文件：

- `rtl/exu/panda_risc_v_wb_pipe.v`
- `rtl/exu/panda_risc_v_wbk.v`
- `rtl/exu/panda_risc_v_commit.v`
- `rtl/exu/panda_risc_v_reg_file.v`

## What Changed From The Original Structure

### 1. IFU output became an explicit `IF/ID` payload

原 IFU 直接把取指结果送给译码/派遣。现在取指结果先进入：

- `panda_risc_v_if_id_pipe`

这个边界锁存：

- `m_if_res_data`
- `m_if_res_msg`
- `m_if_res_id`
- `m_if_res_is_first_inst_after_rst`
- `m_if_res_valid/ready`

这样 IF 和 ID 在文档、波形、RTL 上都有清晰分界。

### 2. Decode/dispatch output became an explicit `ID/EX` payload

原 `dcd_dsptc` 会直接向 ALU、LSU、CSR、MUL、DIV 发请求。现在这些请求先经过：

- `panda_risc_v_id_ex_pipe`

这个边界锁存各执行单元请求，并把译码级和执行级拆开。当前仍保留原有多执行单元请求形式，目的是降低一次性重构风险；但从流水线展示角度，ID 到 EX 已经有明确寄存器边界。

### 3. LSU request path became the visible `EX/MEM` boundary

原 EXU 内部直接处理 LSU 请求。现在 load/store 地址在 EX 形成后，先进入：

- `panda_risc_v_ex_mem_pipe`

然后再送入：

- `panda_risc_v_lsu`

这使 MEM 级入口可见。尤其是 `fence_i`、store/load 顺序和访存异常分析时，可以明确区分“请求还在 EX/MEM 前后”还是“已经进入 LSU”。

### 4. Completion sources became the visible `MEM/WB` boundary

原 EXU 内部多个完成源直接靠写回逻辑仲裁。现在 ALU/CSR、LSU、MUL、DIV 等完成源先进入：

- `panda_risc_v_wb_pipe`

再进入：

- `panda_risc_v_wbk`
- `panda_risc_v_commit`

这使 WB 入口和退休入口在 RTL 中可见。

### 5. Barrier ordering was fixed around the new MEM boundary

加入 `EX/MEM` 边界后，仅看 LSU 本体 idle 不够。旧 store 可能还没进入 LSU，就被后面的屏障指令越过。

当前 `lsu_idle` 语义已经加强，只有同时满足以下条件才认为内存路径空闲：

- EX 当前没有新的 LSU 请求
- `panda_risc_v_ex_mem_pipe` 内没有缓存 LSU 请求
- `panda_risc_v_lsu` 本体空闲

这个改动保证 `fence_i` 等屏障不会越过尚未真正进入 LSU 的旧访存请求。

## How To Read The RTL Quickly

建议按这个顺序：

1. `rtl/panda_risc_v.v`：看 `panda_risc_v_if_id_pipe_u` 和 `panda_risc_v_id_ex_pipe_u`
2. `rtl/decoder_dispatcher/panda_risc_v_id_ex_pipe.v`：看 ID 到 EX 锁存了哪些请求
3. `rtl/exu/panda_risc_v_exu.v`：搜索 `panda_risc_v_ex_mem_pipe_u` 和 `panda_risc_v_wb_pipe_u`
4. `rtl/exu/panda_risc_v_lsu.v`：看 MEM 级实际访存
5. `rtl/exu/panda_risc_v_wbk.v`：看 WB 级写回仲裁
6. `rtl/exu/panda_risc_v_commit.v`：看退休、异常和 flush 相关完成路径

## Verification Baseline

当前记录的 VCS 基线：

- 文档：`doc/rv32ui_regression_20260405.md`
- 脚本：`tb/tb_panda_risc_v/test_isa_vcs.py`
- 结果：`rv32ui-p-*` 共 `39 passed, 0 failed`

推荐命令：

```sh
cd work/600_competition_5stage/tb/tb_panda_risc_v
python3 test_isa_vcs.py --pattern 'rv32ui-p-*.txt' --build-dir /tmp/competition_vcs_rv32ui
```
