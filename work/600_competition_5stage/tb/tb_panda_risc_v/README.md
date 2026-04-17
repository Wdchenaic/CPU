# CPU ISA Simulation

本目录是当前五级流水线 CPU 的 ISA 仿真入口。

## 推荐路径：VCS 回归

VCS 可用时，直接运行：

```sh
cd work/600_competition_5stage/tb/tb_panda_risc_v
python3 test_isa_vcs.py --pattern 'rv32ui-p-*.txt' --build-dir /tmp/competition_vcs_rv32ui
```

说明：

- `--pattern 'rv32ui-p-*.txt'` 会运行 `inst_test` 下的 RV32UI 用例
- `--build-dir` 建议放在 `/tmp` 这类本地 Linux 目录，避免 VMware 共享目录导致 VCS 最终链接失败
- VCS 文件列表来自 `../../doc/competition_5stage_vcs.f`
- 当前记录基线见 `../../doc/rv32ui_regression_20260405.md`

当前已记录结果：

- `rv32ui-p-*`
- `39 passed, 0 failed, total 39`

## 兼容路径：ModelSim Makefile

旧 ModelSim 流程仍保留：

1. 安装 `make`
2. 修改 `Makefile` 中的 `MODELSIM_PATH`
3. 确认 `to_compile/dut` 中使用的是当前项目 RTL，而不是旧 `600_panda_risc_v` RTL
4. 运行：

   ```sh
   python3 test_isa.py --dir_name inst_test
   ```

测试结果会写入 `isa_test_res.txt`。

## 当前 RTL 来源

当前 CPU RTL 位于：

- `../../rtl`

不要再使用旧工程 RTL 作为当前五级流水线验证输入。
