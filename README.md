# CPU Competition Five-Stage Core

本仓库入口只说明当前比赛主线：`work/600_competition_5stage`。

当前处理器是基于原 `600_panda_risc_v` 改造的 RV32 `IF / ID / EX / MEM / WB` 五级流水线、单发射、顺序提交核心。旧版 `600` 文档里“取指 -> 译码 -> 派遣+执行+写回”的描述已经不再作为当前项目说明使用。

## 当前项目位置

- 主工程：`work/600_competition_5stage`
- CPU 顶层：`work/600_competition_5stage/rtl/panda_risc_v.v`
- 五级流水线说明：`work/600_competition_5stage/doc/competition_stage_partition.md`
- RV32UI 回归说明：`work/600_competition_5stage/doc/rv32ui_regression_20260405.md`
- FPGA 快速综合说明：`work/600_competition_5stage/doc/vivado_host_install_and_first_synth.md`

## 当前五级流水线

| 流水级 | 主要职责 | 当前显式边界 |
| --- | --- | --- |
| IF | PC 选择、取指请求、预译码、静态分支预测基础 | `rtl/ifu/panda_risc_v_if_id_pipe.v` |
| ID | 指令译码、寄存器堆读、相关性检查、生成执行请求 | `rtl/decoder_dispatcher/panda_risc_v_id_ex_pipe.v` |
| EX | ALU/CSR 执行、分支确认、访存地址生成、乘除法启动 | `rtl/exu/panda_risc_v_exu.v` |
| MEM | LSU 请求入口、load/store 访问、访存异常路径 | `rtl/exu/panda_risc_v_ex_mem_pipe.v` |
| WB | 写回仲裁、寄存器堆写回、退休/提交入口 | `rtl/exu/panda_risc_v_wb_pipe.v` |

## 原来的三级结构怎么改

原 `600_panda_risc_v` 代码更像三个宏功能块：

| 原结构 | 原职责 | 当前改法 |
| --- | --- | --- |
| IFU | 取指、预译码、PC 更新 | 保留取指能力，在 IF 和 ID 之间加入 `panda_risc_v_if_id_pipe` |
| DCD / Dispatch | 译码、读寄存器、直接派发到多个执行单元 | 作为 ID 级，输出先进入 `panda_risc_v_id_ex_pipe`，再进入 EX |
| EXU | ALU、LSU、CSR、MUL/DIV、写回、提交混在一起 | 拆出 `EX/MEM` 和 `MEM/WB` 可见边界，让访存入口和写回入口独立可说明 |

已经落地的关键变化：

- `IF -> ID`：取指结果经过 `panda_risc_v_if_id_pipe`
- `ID -> EX`：译码/派遣结果经过 `panda_risc_v_id_ex_pipe`
- `EX -> MEM`：LSU 请求路径经过 `panda_risc_v_ex_mem_pipe`
- `MEM/EX completion -> WB`：ALU/CSR/LSU/MUL/DIV 写回源统一经过 `panda_risc_v_wb_pipe`
- `fence_i` 等屏障指令使用更严格的 `lsu_idle` 判定，避免旧 store 仍在 `EX/MEM` 前后时被后续屏障越过

## 快速上手

1. 先读当前项目 README：

   ```sh
   less work/600_competition_5stage/README.md
   ```

2. 看顶层流水线连线：

   ```sh
   less work/600_competition_5stage/rtl/panda_risc_v.v
   less work/600_competition_5stage/rtl/exu/panda_risc_v_exu.v
   ```

3. 有 VCS 时跑 RV32UI 回归：

   ```sh
   cd work/600_competition_5stage/tb/tb_panda_risc_v
   python3 test_isa_vcs.py --pattern 'rv32ui-p-*.txt' --build-dir /tmp/competition_vcs_rv32ui
   ```

4. 有 Vivado 时跑核心快速综合：

   ```sh
   cd work/600_competition_5stage/fpga/vivado_prj
   ./run_core_quick_synth.sh xc7z020clg400-1 panda_risc_v
   ```

## GitHub 内容策略

当前仓库同步时只提交当前比赛主线和必要说明。旧上游参考仓库、历史分析草稿、仿真生成物和本地上下文文件不会进入 GitHub，以免再次出现旧版三级描述和当前五级实现混在一起的问题。
