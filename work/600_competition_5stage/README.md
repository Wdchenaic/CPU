# 600 Competition Five-Stage CPU

本目录是当前比赛主线工程，不再沿用原 `600_panda_risc_v` README 中的旧流水线描述。

当前 CPU 是基于小胖达 `600` 代码改造的 RV32 `IF / ID / EX / MEM / WB` 五级流水线、单发射、顺序提交处理器。原项目的取指、译码/派遣、执行/写回三个宏功能块已经通过显式流水寄存器拆分成当前五级边界。

## 当前特性

- RV32I，保留 M 扩展相关乘除法执行单元
- 五级流水线：`IF -> ID -> EX -> MEM -> WB`
- 显式流水寄存器：`IF/ID`、`ID/EX`、`EX/MEM`、`MEM/WB`
- 静态分支预测基础：BTFN
- 支持 ALU/CSR 短指令旁路，WB 结果也可旁路回译码读寄存器路径
- 支持乘法、除法、加载/存储等多周期路径
- 采用 ICB 数据/指令访问接口
- 保留中断、异常、调试、DCache、FPGA SoC 验证相关代码

暂不支持：

- 浮点扩展 F/D
- 压缩指令扩展 C

## 五级流水线文件速查

| 流水级 | 主要职责 | 关键 RTL |
| --- | --- | --- |
| IF | PC 选择、取指、预译码、预测跳转基础 | `rtl/ifu/panda_risc_v_ifu.v` |
| IF/ID | 锁存取指结果和预译码元数据 | `rtl/ifu/panda_risc_v_if_id_pipe.v` |
| ID | 译码、读寄存器、RAW/WAW 检查、派遣信息生成 | `rtl/decoder_dispatcher/panda_risc_v_dcd_dsptc.v` |
| ID/EX | 锁存 ALU/LSU/CSR/MUL/DIV 执行请求 | `rtl/decoder_dispatcher/panda_risc_v_id_ex_pipe.v` |
| EX | ALU/CSR 执行、分支确认、访存地址生成、乘除法请求 | `rtl/exu/panda_risc_v_exu.v` |
| EX/MEM | 锁存 LSU 请求，使访存入口成为可见 MEM 边界 | `rtl/exu/panda_risc_v_ex_mem_pipe.v` |
| MEM | LSU 访问、load/store 响应、访存异常产生 | `rtl/exu/panda_risc_v_lsu.v` |
| MEM/WB | 锁存 ALU/CSR/LSU/MUL/DIV 写回源 | `rtl/exu/panda_risc_v_wb_pipe.v` |
| WB | 写回仲裁、寄存器堆写回、退休/提交 | `rtl/exu/panda_risc_v_wbk.v`、`rtl/exu/panda_risc_v_commit.v` |

顶层连线从 `rtl/panda_risc_v.v` 开始看。EX、MEM、WB 后半段边界主要在 `rtl/exu/panda_risc_v_exu.v` 里。

## 原三级宏结构到当前五级结构

原 `600_panda_risc_v` 文档把处理器概括为三个宏功能块：取指、译码、派遣+执行+写回。当前项目没有继续使用这个说明，实际改法如下：

| 原宏功能块 | 原来的职责 | 当前五级化处理 |
| --- | --- | --- |
| 取指 | 取指、预译码、更新 PC、输出取指结果 | 保留为 IF，在取指结果后插入 `panda_risc_v_if_id_pipe` |
| 译码/派遣 | 读通用寄存器堆、详细译码、生成各执行单元请求 | 作为 ID，输出先进入 `panda_risc_v_id_ex_pipe` |
| 派遣+执行+写回 | ALU、LSU、CSR、MUL/DIV、提交、写回混在 EXU 内 | 拆出 EX、MEM、WB 入口，LSU 请求走 `panda_risc_v_ex_mem_pipe`，所有写回源走 `panda_risc_v_wb_pipe` |

这次文档清理的原则是：旧的三宏块介绍不再作为当前项目入口保留；当前说明只描述已经落到 RTL 里的五级边界。

## 已经做过的关键改动

- 在 `rtl/panda_risc_v.v` 中实例化 `panda_risc_v_if_id_pipe`，把 IFU 输出变成显式 `IF/ID` 边界
- 在 `rtl/panda_risc_v.v` 中实例化 `panda_risc_v_id_ex_pipe`，把译码/派遣输出变成显式 `ID/EX` 边界
- 在 `rtl/exu/panda_risc_v_exu.v` 中实例化 `panda_risc_v_ex_mem_pipe`，把 LSU 请求入口变成显式 `EX/MEM` 边界
- 在 `rtl/exu/panda_risc_v_exu.v` 中实例化 `panda_risc_v_wb_pipe`，把写回/退休入口变成显式 `MEM/WB` 边界
- 强化 `lsu_idle` 语义：屏障类指令只有在 EX 中无新 LSU 请求、`EX/MEM` 中无缓存 LSU 请求、LSU 本体空闲时才认为内存路径空闲
- 保留原小胖达成熟模块，先建立比赛可说明、可验证、风险较低的五级边界，再继续收敛旁路、互锁和性能优化

## 快速上手路径

建议按这个顺序看代码：

1. `rtl/panda_risc_v.v`：CPU 顶层，先看 `IF/ID` 和 `ID/EX` 两个流水寄存器实例
2. `rtl/ifu/panda_risc_v_ifu.v`：IF 级取指和预译码来源
3. `rtl/decoder_dispatcher/panda_risc_v_dcd_dsptc.v`：ID 级译码、读寄存器、相关性检查
4. `rtl/decoder_dispatcher/panda_risc_v_id_ex_pipe.v`：ID 到 EX 的执行请求锁存
5. `rtl/exu/panda_risc_v_exu.v`：EX、MEM、WB 后半段主线
6. `rtl/exu/panda_risc_v_ex_mem_pipe.v`：EX 到 MEM 的 LSU 请求边界
7. `rtl/exu/panda_risc_v_wb_pipe.v`：MEM/EX 完成源到 WB 的写回边界
8. `doc/competition_stage_partition.md`：五级流水线拆分说明和设计意图

## 仿真回归

VCS 环境可用时，推荐直接跑当前 RV32UI 回归脚本：

```sh
cd work/600_competition_5stage/tb/tb_panda_risc_v
python3 test_isa_vcs.py --pattern 'rv32ui-p-*.txt' --build-dir /tmp/competition_vcs_rv32ui
```

已记录的当前基线见 `doc/rv32ui_regression_20260405.md`：

- `rv32ui-p-*`
- `39 passed, 0 failed, total 39`

旧 ModelSim 流程仍保留在 `tb/tb_panda_risc_v/Makefile` 和 `tb/tb_panda_risc_v/test_isa.py`，但当前 Linux/VCS 回归更适合作为五级分支的快速验证入口。

## FPGA 快速综合

Vivado 可用时，可先跑核心级快速综合：

```sh
cd work/600_competition_5stage/fpga/vivado_prj
./run_core_quick_synth.sh xc7z020clg400-1 panda_risc_v
```

说明见 `doc/vivado_host_install_and_first_synth.md`。

## 目录结构

| 目录 | 说明 |
| --- | --- |
| `rtl` | 当前五级 CPU、cache、debug、peripheral RTL |
| `tb` | 单元测试和 CPU ISA 仿真平台 |
| `doc` | 当前项目设计、回归、综合说明 |
| `fpga` | FPGA SoC 与 Vivado/TD 工程入口 |
| `software` | boot、驱动库、示例软件 |
| `scripts` | 软件编译、镜像生成、UART 烧录脚本 |
| `tools` | OpenOCD 等本地工具 |

## 当前文档口径

当前项目对外统一称为五级流水线 CPU。历史 `600` 上游文档、旧分析草稿和仿真生成目录不再作为当前项目入口同步到 GitHub。
