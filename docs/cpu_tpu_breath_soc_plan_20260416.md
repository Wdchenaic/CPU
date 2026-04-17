# CPU+TPU 呼吸识别 SoC 方案（2026-04-16）

## 1. 目标和当前边界

本文档锁定当前阶段的实现边界：

- 不改现有 `tpu-soc` 的 2x2 TinyTPU 核心 RTL 能力边界。
- 不强行把整套呼吸识别模型全部塞进 TPU。
- 当前阶段把系统做成一个真实的异构 SoC：
  - `CPU` 负责预处理、1D CNN 分支、任务调度和结果回收。
  - `TPU` 负责最像矩阵乘的 `MLP/Linear` 子图。
  - `descriptor + DMA + shared SRAM + AXI interconnect/arbiter` 负责数据面。
- 后续若要重构更强硬件加速器，单独在“未来计划重构硬件加速”目录推进，不影响当前主线。

一句话收口：

`当前版本先做 CPU+TPU 协同的异构 SoC；CPU 跑 CNN 和预处理，TPU 跑多个 MLP/分类头，利用 shared SRAM、DMA 和多次调用实现时间换面积。`

## 2. 真实算法边界

### 2.1 数据链路

当前呼吸识别算法的数据入口和预处理是：

- 每个 CSV 先做长度 `1000` 的滑动窗口。
- 步长 `500`。
- 每个窗口提取 `8` 个统计特征：
  - dominant frequency
  - std
  - mean
  - peak-to-peak
  - skewness
  - kurtosis
  - energy
  - zero crossing rate
- 模型输入同时包含：
  - `features [B, 8]`
  - `raw_signal [B, 1000]`

### 2.2 模型结构

当前模型不是单一 MLP，而是三路分支加分类头：

1. 关键特征分支 `PerceptronSubNetwork`
- 输入：`2` 维（dominant_freq + std）
- 结构：`2 -> 32 -> 64 -> 128 -> 64 -> 32`

2. 原始波形分支 `CNN1D_TemporalExtractor`
- 输入：`1000` 点原始 1D 信号
- 结构大致：
  - `1 -> 32, k=7`
  - `32 -> 64, k=5`
  - `64 -> 128, k=3`
  - `128 -> 256, k=3`
- 中间包含：
  - `BatchNorm1d`
  - `ReLU`
  - `MaxPool1d`
  - `AdaptiveAvgPool1d`
  - `FiLM` 条件调制

3. 其余特征分支 `OtherFeaturesEncoder`
- 输入：`6` 维辅助特征
- 结构：`6 -> 32 -> 32`

4. 分类头 `BreathClassifier.classifier`
- 融合后向量维度：`322`
- 结构：`322 -> 256 -> 128 -> 64 -> 4`

## 3. 为什么当前 2x2 TinyTPU 不直接承接整个模型

当前 `tpu-soc` 的 TinyTPU 最扎实的能力边界仍然是：

- `2x2` systolic array
- `Q8.8`
- 小型 `MLP/Linear` 路线
- 当前控制/数据链路围绕 `frontend + UB + IMEM` 驱动的小规模流程构建

### 3.1 从规模上看

- `2x2` 阵列不是不能做更大 MLP。
- 但它只能通过 `tile + 多次调用 + 时间换面积` 来做。
- 这对 `MLP/Linear` 是成立的。

### 3.2 从算子种类上看

当前 TinyTPU 并没有自然支持整套：

- `Conv1d`
- `BatchNorm`
- `MaxPool`
- `AdaptiveAvgPool`
- `FiLM`
- `concat`

这意味着：

- 对 `纯 MLP/Linear` 子图，当前 TPU 适合继续扩成 tile 执行。
- 当前 Stage2 RTL 和 CPU 软件 demo 已验证 `flags[16]` 的 multi-tile 2x2 Q8.8 MAC，并通过 `output_words=16 / param_words=48` 跑通 `2 -> 32` 第一层雏形。
- 对 `1D CNN` 分支，当前 TPU 不适合直接承接，除非后续做较大规模硬件重构。

## 4. 当前阶段的 CPU/TPU 最优切分

### 4.1 CPU 负责的内容

当前阶段放到 CPU 的任务：

- 滑动窗口切分
- `8` 个统计特征提取
- `1D CNN` 分支
- `BatchNorm / Pool / FiLM` 相关流程
- 多个 TPU 子任务的调度
- 融合向量的组织
- 最终结果回收、分类输出和 debug

### 4.2 TPU 负责的内容

当前阶段放到 TPU 的任务：

- 关键特征分支 MLP
  - `2 -> 32 -> 64 -> 128 -> 64 -> 32`
- 其余特征分支 MLP
  - `6 -> 32 -> 32`
- 分类头 MLP
  - `322 -> 256 -> 128 -> 64 -> 4`

### 4.3 切分后的好处

- 不改当前加速器大方向。
- 保留 `2x2` TinyTPU 的简洁面积优势。
- 真正用上 `descriptor + DMA + shared SRAM + arbiter`，不是只做寄存器 demo。
- 更符合“用时间换面积”的面试叙事。

一句话：

`CNN 留在 CPU，MLP/分类头放到 TPU。`

## 5. 固定表是什么意思

固定表不是降低灵活性，而是把“网络结构元信息”从每次任务里拿出来，变成一张静态表。

也就是说：

- `descriptor` 只描述“这次任务怎么跑”。
- `固定表` 描述“这个网络本身长什么样”。

推荐在 CPU 固件中维护一张静态表：

```c
typedef struct {
    uint32_t net_id;
    uint32_t family;        // MLP / CNN1D / HEAD
    uint32_t imem_slot;     // 对应哪套微程序
    uint32_t input_words;
    uint32_t output_words;
    uint32_t param_words;
    uint32_t need_scratch;
} tpu_net_meta_t;
```

### 5.1 推荐的 net_id 划分

```c
enum {
    NET_ID_MLP_KEY        = 0, // 2 -> 32 -> 64 -> 128 -> 64 -> 32
    NET_ID_MLP_OTHER      = 1, // 6 -> 32 -> 32
    NET_ID_CLASSIFIER     = 2, // 322 -> 256 -> 128 -> 64 -> 4
    NET_ID_CNN1D_RESERVED = 3  // 未来重构硬件加速时占位
};
```

### 5.2 为什么不用“大而全 descriptor”

如果把每层维度、激活、卷积核、池化、布局、地址列表都塞进 descriptor，descriptor 会膨胀成“小编译器输入”，导致：

- RTL 状态机复杂化
- 软件接口复杂化
- 验证复杂化
- 当前三周目标失控

当前阶段更合理的是：

- 固定网络结构放 `固定表`
- 每次任务只传输入输出地址、参数地址、scratch 地址和 flags

## 6. param_pool 是什么意思

`param_pool` 指的是：

- 上电或初始化时
- CPU 把所有固定子网络的参数 blob 一次性写进 shared SRAM 的固定参数区
- 后续每次推理不再重写整包参数，只切换 `net_id` 和任务 descriptor

示例布局：

```text
0x6000_0000  param_pool.mlp_key
0x6000_2000  param_pool.mlp_other
0x6000_4000  param_pool.classifier_head
0x6000_8000  param_pool.cnn1d_reserved
```

这样做的好处：

- CPU 软件开销更小
- 不必每次重复搬运权重
- 更符合 SoC 和 runtime 的真实形态
- 更容易做双缓冲和批量任务调度

## 7. 当前阶段推荐的 descriptor

当前阶段不做通用 AI runtime，做“面向当前固定子网络家族的相对通用 descriptor”：

```c
typedef struct {
    uint32_t net_id;        // 跑哪个子网络
    uint32_t input_addr;    // 输入地址
    uint32_t output_addr;   // 输出地址
    uint32_t param_addr;    // 参数基址
    uint32_t scratch_addr;  // 工作区，中间缓冲
    uint32_t input_words;   // 输入长度
    uint32_t output_words;  // 输出长度
    uint32_t flags;         // relu / buf_sel / debug / tile2x2_q8_8 / reserved
} tpu_desc_t;
```

这个 descriptor 可以覆盖：

- 小 MLP
- 更大层数的 MLP
- 分类头
- 后续可能加入的简化卷积块

当前 RTL 已落地一个受控的 tile 特例：`flags[16] = TPU_DESC_F_TILE2X2_Q8_8` 时，DMA 不再按固定表抓参数，而是按 `output_words * 3` 抓参数；每个 output word 是两个 Q8.8 输出 lane。

它的边界是：

- 还不是图执行 runtime
- 还不承载完整 layer graph
- 不替代固定表

## 8. 最终 SoC 架构

### 8.1 总体结构

```text
CPU core
  -> panda_risc_v_min_proc_sys

控制面:
  m_axi_dbus_* -> TPU_CTRL(AXI-Lite) [+ UART 可选]

数据面:
  m_axi_dcache_* ----\
                      -> AXI interconnect/arbiter -> shared SRAM
  TPU DMA master -----/
```

### 8.2 shared SRAM 推荐布局

```text
0x6000_0000  param_pool.mlp_key
0x6000_2000  param_pool.mlp_other
0x6000_4000  param_pool.classifier_head
0x6000_8000  param_pool.cnn1d_reserved

0x6001_0000  desc0
0x6001_0100  in_buf0
0x6001_0400  out_buf0
0x6001_0800  scratch0

0x6001_1000  desc1
0x6001_1100  in_buf1
0x6001_1400  out_buf1
0x6001_1800  scratch1
```

其中：

- `desc0/desc1` 用于双缓冲任务描述
- `in_buf0/in_buf1` 用于双缓冲输入
- `out_buf0/out_buf1` 用于双缓冲输出
- `scratch0/scratch1` 用于中间工作区

## 9. 当前算法在 SoC 里的执行顺序

推荐的软件执行链：

```text
CSV
 -> CPU滑窗
 -> CPU提取8个统计特征
 -> CPU执行1D CNN分支
 -> CPU组织TPU输入
 -> CPU写descriptor到shared SRAM
 -> CPU通过TPU_CTRL启动TPU
 -> TPU DMA取descriptor和数据
 -> TPU执行MLP_key / MLP_other / classifier_head
 -> TPU DMA写回结果
 -> CPU回收结果并完成最终融合/输出
```

### 9.1 更细的分阶段流程

1. `Boot` 阶段
- CPU 初始化系统
- CPU 把各子网络参数写到 `param_pool`
- CPU 初始化固定表 `tpu_net_meta_t[]`

2. 每个样本窗口阶段
- CPU 从 CSV/缓存中取出 `1000` 点窗口
- CPU 提取 `8` 个统计特征
- CPU 在本地执行 `1D CNN` 分支，得到 `256` 维时序特征
- CPU 根据需要触发 TPU 子任务：
  - `NET_ID_MLP_KEY`
  - `NET_ID_MLP_OTHER`
  - `NET_ID_CLASSIFIER`

3. TPU 子任务阶段
- CPU 把子任务输入写入 `in_bufX`
- CPU 填好 `descX`
- CPU 写 `TPU_CTRL` 触发 DMA 和执行
- TPU 从 `shared SRAM` 取输入和参数
- TPU 执行 tile 化 MLP
- TPU 把输出写回 `out_bufX`

4. 结果收尾阶段
- CPU 读 `out_bufX`
- CPU 完成融合或最终分类
- CPU 输出结果或写 signature/debug 区

## 10. 双缓冲和并发意义

当前推荐双缓冲：

- `buf0` 给 TPU 当前任务使用
- `buf1` 给 CPU 准备下一任务/下一窗口

运行形态：

- TPU 在 DMA 读 `buf0` 时
- CPU 同时往 `buf1` 写下一组输入或 descriptor

这样带来两点收益：

- 吞吐更高
- `CPU` 和 `TPU DMA` 会真实争用 `shared SRAM`

这时 `interconnect/arbiter` 才是系统主路径上的真实工程点，而不是摆设。

## 11. 当前阶段不做的事情

为保证边界收口，当前阶段明确不做：

- 不把完整 `1D CNN + FiLM + Pool + BN` 都硬化到当前 TinyTPU
- 不先扩阵列到 `4x4` 或更大
- 不做大而全通用 graph runtime
- 不先追求 custom instruction 全栈闭环
- 不先做 DDR
- 不先做复杂 cache coherency 系统；当前 shared SRAM 段先通过 `ext_mem_uncached="true"` 做成 uncached 区

## 12. 当前阶段最该推进的内容

优先顺序建议：

1. `descriptor`
2. `fixed table`
3. `param_pool`
4. `TPU DMA`
5. `shared SRAM`
6. `AXI interconnect/arbiter`
7. `tile 调度`
8. 双缓冲与并发验证

也就是说，优先改的是：

- 软件/runtime
- descriptor
- DMA
- shared SRAM
- tile 调度

而不是优先改大硬件阵列。

## 13. 未来硬件重构方向

如果后续要真正承接 `CNN1D` 分支，建议单独在未来重构分支推进，而不要污染当前主线。

未来重构方向包括：

- 专用 `Conv1D` 数据通路
- line buffer / window buffer
- 后处理单元：`scale+bias / ReLU / pooling`
- 更通用的 vector/post-process block
- 更强的调度器和 scratchpad 组织
- 必要时扩大阵列，而不是盲目先改阵列

当前仓库中，这条未来线已经单独隔离到：

- `/home/jjt/soc/my_soc/未来计划重构硬件加速/`

该目录用于后续探索：

- `tpu-soc`
- `verilog-axi`
- `arbiter`

## 14. 最短结论

- 固定表：保存固定子网络的结构元信息，不把层细节塞进 descriptor。
- `param_pool`：所有固定权重在 boot 时一次性放进 shared SRAM 固定参数区。
- 当前 `2x2` TinyTPU 不适合直接吃完整个 `MLP + 1D CNN + FiLM + classifier` 模型。
- 当前最合理路线：
  - `CPU` 跑滑窗、特征提取、CNN 分支和调度
  - `TPU` 跑关键特征 MLP、辅助特征 MLP、分类头
  - 靠 `descriptor + DMA + shared SRAM + 多次调用 + 双缓冲` 做成真实异构 SoC
- 当前已验证到 CPU 可通过 C 程序发起 `2 -> 32` 第一层 tile 子任务；下一步是 layer schedule / scratch / ReLU，把它推进成多层 MLP 子网。
