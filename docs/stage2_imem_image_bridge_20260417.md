# Stage2 CPU Demo IMEM Image Bridge

## 目的
把已经编译好的 `breath_tpu_soc_demo.bin` 转成 `panda_soc_stage2_base_top` 可直接引用的 IMEM 初始化文件。

## 输入程序
- `work/600_competition_5stage/software/test/breath_tpu_soc_demo/breath_tpu_soc_demo.bin`

## 生成脚本
- `work/600_competition_5stage/scripts/gen_imem_init_roms.py`

该脚本会生成：
- 整字版 `*.txt`
- 四个字节 lane 文件 `*_b0.txt` `*_b1.txt` `*_b2.txt` `*_b3.txt`

字节顺序与原工程 `boot_rom.txt / boot_rom_b0..b3.txt` 一致：
- `b0` 是最低字节
- `b3` 是最高字节

## 当前已生成文件
目录：
- `work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo`

文件：
- `breath_tpu_soc_demo_imem.txt`
- `breath_tpu_soc_demo_imem_b0.txt`
- `breath_tpu_soc_demo_imem_b1.txt`
- `breath_tpu_soc_demo_imem_b2.txt`
- `breath_tpu_soc_demo_imem_b3.txt`

## 在 stage2 top 中的用法
实例化 `panda_soc_stage2_base_top` 时传入：

```verilog
.imem_init_file(".../breath_tpu_soc_demo_imem.txt"),
.imem_init_file_b0(".../breath_tpu_soc_demo_imem_b0.txt"),
.imem_init_file_b1(".../breath_tpu_soc_demo_imem_b1.txt"),
.imem_init_file_b2(".../breath_tpu_soc_demo_imem_b2.txt"),
.imem_init_file_b3(".../breath_tpu_soc_demo_imem_b3.txt")
```

## 当前边界
这一步只打通了：
- `CPU C 程序 -> bin -> IMEM init files`

还没有完成：
- `CPU 真正在 stage2 top 中从 IMEM 启动`
- `CPU 通过 MMIO 写 0x4000_4000 并驱动当前 RTL 主路径`

但这已经把下一步 CPU 真跑 RTL 所需的软件镜像准备好了。
