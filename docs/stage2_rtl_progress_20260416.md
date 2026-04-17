# Stage2 RTL 进展（2026-04-16）

## 当前已落地的 RTL / TB 骨架

已新增：

- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/panda_soc_shared_mem_subsys.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/panda_soc_stage2_base_top.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/cpu_tpu_axil_splitter.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_ctrl_axil_regs.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_ctrl_task_stub.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_desc_fetch_dma_stub.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/rtl/tpu_mlp_compute_stub.v`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_tpu_ctrl_task_stub.sv`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_tpu_desc_fetch_dma_stub.sv`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_tpu_ctrl_task_stub.sh`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_tpu_desc_fetch_dma_stub.sh`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_stage2_elab_full.sh`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/tb_tpu_ctrl_dma_integration.sv`
- `work/600_competition_5stage/fpga/panda_soc_eva/tb/run_vcs_tpu_ctrl_dma_integration.sh`

## 1. panda_soc_shared_mem_subsys.v

该模块实现的是第二阶段数据面的独立子系统骨架：

```text
CPU dcache AXI master
          \
           -> axi_interconnect -> axi_ram(shared SRAM)
          /
TPU DMA AXI master
```

该模块当前负责：

- 接收 CPU `m_axi_dcache_*` 风格接口
- 预留 TPU DMA 第二个 AXI master 接口
- 用 `verilog-axi/axi_interconnect.v` 做共享互连
- 用 `verilog-axi/axi_ram.v` 做 shared SRAM 后端
- 把 shared SRAM 地址窗口锁在 `0x6000_0000` 段

## 2. cpu_tpu_axil_splitter.v

该模块实现 CPU 控制面的地址分流：

```text
CPU m_axi_dbus_*
  |- legacy AXI-Lite -> AXI-APB bridge -> UART
  |- TPU_CTRL AXI-Lite -> tpu_ctrl_axil_regs
```

当前负责：

- 把 `0x4000_4000 ~ 0x4000_4FFF` 路由到 `TPU_CTRL`
- 其他控制面地址继续走 legacy 外设路径
- 保持 CPU 侧仍然只看到一条外设控制总线

## 3. tpu_ctrl_axil_regs.v

该模块实现第二阶段最小 `TPU_CTRL` 寄存器块，当前已包含：

- `CTRL`
- `STATUS`
- `MODE`
- `NET_ID`
- `DESC_LO`
- `DESC_HI`
- `PERF_CYCLE`

并对外导出：

- `launch_pulse`
- `soft_reset_pulse`
- `mode_reg`
- `net_id_reg`
- `desc_lo_reg`
- `desc_hi_reg`
- `irq_en_reg`
- `perf_cycle_reg`

## 4. tpu_ctrl_task_stub.v

该模块是控制面占位状态机，在真实 TPU DMA / launch engine 接入前提供最小闭环：

```text
CPU MMIO write CTRL/DESC/MODE/NET_ID
  -> TPU_CTRL regs
  -> task stub
  -> busy / done / error
```

当前行为：

- 收到 `launch_pulse` 后，如果 `desc_lo_reg != 0`，进入 `busy`
- 经过固定延迟后拉起 `done`
- 如果 `desc_lo_reg == 0`，拉起 `error`
- 收到 `soft_reset_pulse` 后清空 `busy/done/error`

它不是最终功能实现，只是为了把 CPU 控制面先闭合起来。

## 5. tpu_desc_fetch_dma_stub.v

该模块是当前第一版数据面原型：

```text
launch + desc_base
  -> TPU DMA stub 发起 AXI 读
  -> 从 shared SRAM 抓 8-word descriptor
  -> 按 descriptor 抓 input blob
  -> 默认按 net_id 固定表抓 param blob；flags[16] tile 模式按 output_words*3 抓 param blob
  -> 以 word_valid 流式喂给 tpu_mlp_compute_stub
  -> 由 compute stub 生成 output word
  -> DMA 写回 output blob
  -> done / error
```

当前边界：

- 先抓取 8-word descriptor
- 再按 descriptor 的 `input_addr/input_words` 抓 input blob
- 再按 `net_id` 对应固定表抓 param blob；如果 `flags[16]` 进入 `TILE2X2_Q8_8` 模式，则按 `output_words * 3` 动态抓参数
- input/param fetch 结果通过 `input_word_valid/input_word` 和 `param_word_valid/param_word` 流式送进 `tpu_mlp_compute_stub`
- 最后按 `output_addr/output_words` 把 compute stub 的最小结果写回 output blob
- 当前 output 已有两种模式：
  - 默认兼容模式：`output_word[i] = input_checksum + param_checksum + net_id + flags + i`
  - `flags[16]` tile 模式：执行 multi-tile 2x2 Q8.8 MAC，输入/权重/偏置按两个 16-bit lane 打包；每个 output word 对应一个 2-output tile，参数消耗 3 word，`param_words = output_words * 3`
- 仍保留输入侧最小统计寄存器，但这些调试值已经由 compute stub 侧维护：
  - `input_fetch_word_count`
  - `input_checksum`
  - `input_last_word`
  - `param_fetch_word_count`
  - `param_checksum`
  - `param_last_word`
- `done/error` 状态保持到下一次 launch 或 soft reset

这个模块的价值是：

- 已经把 `descriptor -> input -> param -> output` 的最小数据闭环链接起来了
- 已经把 `TPU_CTRL -> descriptor base -> AXI master -> shared SRAM` 往前推进到真正的读写搬运
- 下一步可以在这个基础上继续长出真实 TPU core 接口和结果回写替换

## 6. panda_soc_stage2_base_top.v

该模块实现的是第二阶段基座顶层骨架：

```text
panda_risc_v_min_proc_sys
  |- m_axi_dbus_*   -> cpu_tpu_axil_splitter
  |                    |- UART/APB legacy path
  |                    |- TPU_CTRL AXI-Lite regs
  |
  |- m_axi_dcache_* -> panda_soc_shared_mem_subsys

panda_soc_shared_mem_subsys
  |- CPU dcache master
  |- TPU DMA master (internal DMA stub by default / external future path)
  |- shared SRAM
```

当前基座顶层边界：

- 已保留 CPU 子系统
- 已保留 UART 最小外设通路
- 已把 CPU 控制面分成 `UART + TPU_CTRL`
- 已接入 shared SRAM 数据面
- 已把 `descriptor/input/param DMA stub` 挂回统一 launch/status 和 AXI 主路径
- 已保留外部 `tpu_axi_*` / `tpu_status_*` 口，后续可切回真实外部 TPU wrapper
- 已把 TPU 任务级控制寄存器在顶层引出
- 当前默认优先使用内部 DMA stub；task stub 退成更小的控制面后备路径

## 7. tb_tpu_ctrl_task_stub.sv

该 directed testbench 不跑完整 SoC，只验证最小控制面链路：

```text
AXI-Lite master model
  -> tpu_ctrl_axil_regs
  -> tpu_ctrl_task_stub
```

当前覆盖了：

- reset 后 `STATUS=0`
- 配置 `MODE/NET_ID/DESC`
- `CTRL.start` 后 `busy` 拉起
- 若干周期后 `done` 拉起
- `PERF_CYCLE` 在 `busy` 期间递增
- `DESC_LO=0` 时 `error` 拉起
- `CTRL.soft_reset` 后状态清零

## 8. tb_tpu_desc_fetch_dma_stub.sv

该 unit test 聚焦当前第一步数据面：

```text
shared SRAM model
  <- panda_soc_shared_mem_subsys <- TPU descriptor DMA stub
```

当前覆盖了：

- 直接向 shared SRAM 模型预装：
  - 8-word descriptor
  - input blob
  - param blob
  - output blob 初值
- 通过 `launch + desc_base` 触发 DMA stub
- DMA stub 通过 AXI 依次执行：
  - 读取 descriptor
  - 读取 input
  - 读取 param
  - 回写 output
- 校验 descriptor 8 个字段都被正确解析
- 校验 input fetch 的 `count/checksum/last_word`
- 校验 param fetch 的 `count/checksum/last_word`
- 校验 output blob 被按预期模式写回
- 新增校验 `flags[16]` 的 multi-tile 2x2 Q8.8 MAC：`x=[1.0,2.0]` 时输出 `0xFF80_0B40` 和 `0x0020_01C0`
- 新增 `2 -> 32` 第一层形态 directed test：`output_words=16`，DMA 自动拉取 `48` 个参数并写回 16 个 packed output word
- 校验 CPU 背景 AXI write 也能在 DMA busy 期间完成
- `soft_reset` 后状态清零
- `desc_base = 0` 时 `error` 路径正确

注意：

- 这个 test 当前为了聚焦 DMA 读路径，descriptor/input/param 采用对 `axi_ram` 的直接预装
- `CPU AXI write preload -> shared SRAM` 这条路径，后面会单独做 directed test

## 9. tb_tpu_ctrl_dma_integration.sv

该 integration test 把控制面和数据面真正接在一起，但不带完整 CPU 内核：

```text
AXI-Lite master model
  -> tpu_ctrl_axil_regs
  -> launch/status/perf
  -> tpu_desc_fetch_dma_stub
  -> panda_soc_shared_mem_subsys
  -> shared SRAM
```

当前覆盖了：

- 通过 AXI-Lite 真实访问 `TPU_CTRL`：
  - `STATUS` 初值读取
  - `MODE / NET_ID / DESC_LO / DESC_HI` 配置
  - `CTRL.start` 启动
  - `STATUS.done/error` 轮询
  - `PERF_CYCLE` 回读
  - `CTRL.soft_reset` 清零
- 通过 shared SRAM 预装 descriptor/input/param
- 检查 DMA stub 回写 output blob
- 检查 `desc_base = 0` 时 error 路径

这个 test 的意义是：

- 它已经把 `TPU_CTRL -> DMA stub -> shared SRAM -> STATUS/output` 主路径闭合了
- 不再只是分散的 control-only / DMA-only 单测
- 后续替换成真实 TPU wrapper / datapath 时，可以直接沿着这条集成链演进

## 当前还没接上的部分

当前还缺：

- 用真实 TPU wrapper / tiled MLP datapath 替换当前 `tpu_mlp_compute_stub`
- `TPU core / wrapper` 到 `TPU_CTRL` 的真实功能闭环
- 当前 DMA 仍是系统级原型，后续需要逐步替换成真实 TPU input/param 装载与 output 回写控制
- `tb_panda_soc_stage2_smoke.sv` 仍未收口，但 CPU boot 顶层功能仿真已经覆盖主链

## 当前验证状态

### 已通过的检查

1. `panda_soc_shared_mem_subsys.v` 已通过最小 `VCS` 语法编译
   - 编译文件：
     - `verilog-axi/rtl/axi_interconnect.v`
     - `verilog-axi/rtl/axi_ram.v`
     - `panda_soc_shared_mem_subsys.v`

2. `panda_soc_stage2_base_top.v` 已通过混合语言模式下的完整 `VCS` elaboration
   - UART 相关 legacy RTL：`apb_uart.v / uart_rx_tx.v / uart_tx.v / uart_rx.v` 用 `+v2k`
   - 其余 FPGA SoC RTL 与 `verilog-axi` 用 `-sverilog`
   - 当前 `stage2 top` 已经默认把内部 DMA stub 接回 launch/status + shared SRAM AXI 主路径
   - 顶层 `simv_stage2_elab_full` 已成功生成
   - 当前保留若干 legacy lint warning（如 `TFIPC/SIOB/PCWM`），但不阻塞顶层结构闭合
   - 新增并通过检查的文件包括：
     - `cpu_tpu_axil_splitter.v`
     - `tpu_ctrl_axil_regs.v`
     - `tpu_ctrl_task_stub.v`
     - `tpu_desc_fetch_dma_stub.v`
     - `tpu_mlp_compute_stub.v`

3. `tb_tpu_ctrl_task_stub.sv` 已通过 `VCS` 编译 + 运行
   - 实际仿真输出：
     - `busy asserted after launch`
     - `done observed after 3 polls`
     - `perf counter incremented to 8`
     - `error path observed as expected`
     - `TPU_CTRL + task stub directed test passed`

4. `tb_tpu_desc_fetch_dma_stub.sv` 已通过 `VCS` 编译 + 运行
   - 实际仿真输出：
     - `DMA busy asserted`
     - `descriptor/input/param fetched, output written back, and cpu background writes completed through shared SRAM`
     - `q8.8 multi-tile 2x2 MAC outputs matched expected packed results`
     - `q8.8 2-to-32 tiled MAC outputs matched expected packed results`
     - `descriptor/input/param/output DMA stub test with cpu background traffic passed`

5. `tb_tpu_ctrl_dma_integration.sv` 已通过 `VCS` 编译 + 运行
   - 实际仿真输出：
     - `integrated TPU_CTRL busy asserted after start`
     - `integrated TPU_CTRL done observed after 48 polls`
     - `TPU_CTRL + DMA stub + shared SRAM integration test passed`

6. `tb_panda_soc_stage2_cpu_boot.sv` 已通过 `VCS` 编译 + 运行
   - 修复点：
     - `panda_risc_v_reset` 已接入 `stage2 top`，CPU 能从 `0x0000_0800` 正常启动
     - `gen_imem_init_roms.py` 已支持 `--start-addr`，IMEM 装载地址与 CPU 复位 PC 对齐
     - `panda_risc_v_min_proc_sys` 新增 `ext_mem_uncached` 旁路模式，`0x6000_0000` shared SRAM 可绕过 DCache 以单拍 AXI 直达
   - 实际仿真输出：
     - `observed launch #1/#2/#3`
     - launch #1 已由 CPU 软件以 `flags=0x00010001` 触发 `NET_ID=0` 的 `TILE2X2_Q8_8` 模式
     - launch 时 `desc/input/param` 在 shared SRAM 中均为非零且内容正确
     - `cpu boot launched all three stages and shared SRAM contents match expectations`
     - `CPU top-level stage2 boot test passed`
   - 2026-04-17 已在软件重编译与 IMEM 重新生成后再次通过该 CPU boot 顶层仿真
   - CPU boot TB 已检查 stage0 `2 -> 32` tile 输出：`out0[0]=0x02000100`、`out0[15]=0x20001000`

7. `tpu_mlp_compute_stub.v` 已接入 DMA 写回路径
   - 默认路径仍保留 checksum-compatible placeholder，保证现有 CPU boot demo 不变
   - `flags[16]` 已启用 multi-tile 2x2 Q8.8 MAC tile 模式，完成从 input/param 到 packed output 的真实乘加
   - tile 模式参数长度由 descriptor 的 `output_words` 推导：每个 output word 消耗 3 个 param word，因此 `2 -> 32` 第一层形态为 `output_words=16 / param_words=48`
   - 当前已经形成流式 input/param 边界：DMA 读到每个 input/param word 后，用 `*_word_valid` 喂给 compute block
   - `input_fetch_word_count/input_checksum/input_last_word` 与 `param_fetch_word_count/param_checksum/param_last_word` 已由 compute block 侧维护
   - 改动目标是把 `DMA 数据搬运` 和 `compute 结果生成` 拆开，后续可把 tile 内部替换成真实 TinyTPU systolic/PE 或扩成多 tile MLP datapath
   - 已重新通过：
     - `tb_tpu_desc_fetch_dma_stub.sv`
     - `tb_tpu_ctrl_dma_integration.sv`
     - `tb_panda_soc_stage2_cpu_boot.sv`

8. `tb_panda_soc_stage2_smoke.sv` 当前仍在调试中
   - `panda_soc_stage2_base_top` 本身的完整 elaboration 已经通过
   - 但当前 smoke TB 采用层次 `force` 驱动 top 内部控制面时，读响应路径仍存在 testbench 级驱动问题
   - 这不影响上面的集成级 `TPU_CTRL + DMA stub + shared SRAM` 主路径验证结果

### 还没做的验证

- 基于 `panda_soc_stage2_base_top` 的 CPU boot 顶层功能仿真已经通过，但 `smoke TB` 仍未收口
- `tb_panda_soc_stage2_smoke.sv` 仍需把层次驱动方式收口成稳定的 top-level MMIO BFM
- 真实 CPU 程序已经通过 `0x4000_4000` 发起 3 次 launch，并驱动 shared SRAM descriptor/input/param 路径
- `CPU preload descriptor -> DMA fetch descriptor -> launch` 的完整链已经验证通过
- 当前 compute placeholder 已从 DMA stub 中拆出，但还没有替换成真实 TPU wrapper/DMA/compute datapath

## 本地重跑方式

控制面 directed test：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_tpu_ctrl_task_stub.sh
```

descriptor fetch DMA unit test：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_tpu_desc_fetch_dma_stub.sh
```

TPU_CTRL + DMA + shared SRAM integration test：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_tpu_ctrl_dma_integration.sh
```

CPU boot top-level test：

```bash
cd work/600_competition_5stage/fpga/panda_soc_eva/tb
./run_vcs_stage2_cpu_boot.sh
```

## 下一步最值钱的工作

1. 在 `NET_ID=0` 上补 layer schedule / scratch / ReLU，把已接入 CPU demo 的 `2 -> 32` 第一层推进到多层关键特征 MLP
2. 把 DMA 原型的 input/param fetch 结果转成 TinyTPU 可消费的 UB/load 接口
3. 后续再把 tile 内部替换为真实 TinyTPU systolic/PE，扩到 `NET_ID=1/2`
4. `tb_panda_soc_stage2_smoke.sv` 可后补，当前优先级低于真实 compute datapath 替换
