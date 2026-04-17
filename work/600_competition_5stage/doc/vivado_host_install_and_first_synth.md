# Host Vivado Install And First Synth

## Recommended setup

- host OS: `Windows 10 Pro/Enterprise 22H2`
- install both `Vivado` and `Codex` on the host
- keep the project on a host-local path such as `D:\CPU_Copetition`
- avoid VMware shared folders for synthesis runs

## Why host install is preferred

- GUI responsiveness is much better than inside the VM
- JTAG / cable setup is simpler
- large project I/O is more reliable on host-local disk
- a host-side Codex session can call `vivado` directly in batch mode

## Tool-role split

- `dc_shell` can replace `yosys` for early logic-area and timing-trend checks
- neither `dc_shell` nor `yosys` can replace `Vivado` for final FPGA numbers
- the competition-facing numbers still need real `Vivado` reports for `LUT / FF / BRAM / DSP / FPGA Fmax`

## Board / part assumption for the first run

The upstream FPGA notes under `repos/upstream/Opensoc/600_panda_risc_v/fpga/vivado_prj/README.md` say the reference board is `zynq7020`, so the default quick-synth assumption in this branch is:

- part: `xc7z020clg400-1`
- top: `panda_risc_v`
- mode: out-of-context core-only synthesis

If your actual board package differs, change the `part` argument only; the first quick-synth flow does not depend on board I/O yet.

## Minimum host checks

Run these in a host terminal after installation:

```bat
where vivado
vivado -version
```

## Existing host scripts in this branch

- launcher: `fpga/vivado_prj/run_core_quick_synth.bat`
- launcher: `fpga/vivado_prj/run_core_quick_synth.sh`
- batch Tcl: `fpga/vivado_prj/scripts/run_core_quick_synth.tcl`

## One-command batch run on host

From the project root on the host:

```bat
fpga\vivado_prj\run_core_quick_synth.bat xc7z020clg400-1 panda_risc_v
```

## What the Tcl script does

- reads the current 5-stage RTL directly from `work/600_competition_5stage/rtl`
- includes these RTL trees:
  - `rtl`
  - `rtl/generic`
  - `rtl/ifu`
  - `rtl/decoder_dispatcher`
  - `rtl/exu`
  - `rtl/system`
  - `rtl/debug`
  - `rtl/cache`
  - `rtl/peripherals`
- runs `synth_design -mode out_of_context`
- emits the first resource/timing reports

## Output reports

Reports are written to:

- `fpga/vivado_prj/runs/core_quick_synth/utilization_synth.rpt`
- `fpga/vivado_prj/runs/core_quick_synth/utilization_hier_synth.rpt`
- `fpga/vivado_prj/runs/core_quick_synth/timing_synth.rpt`
- `fpga/vivado_prj/runs/core_quick_synth/post_synth.dcp`

## What this first flow is for

- verify that `Vivado` can read the current 5-stage RTL directly
- get real FPGA `LUT / FF / BRAM` numbers for the core
- compare measured core-only utilization against the current structural estimate of roughly `3200 ~ 4300 LUT` for the submission-oriented configuration

## What this first flow is not yet for

- not a full board bitstream
- not a final `minimal-proc-system` utilization number
- not the final competition submission build

## Recommended next FPGA step after quick synth

After the core-only report is healthy, the next step should be a cleaned-up `minimal-proc-system` Vivado flow that points to the new 5-stage core RTL rather than the older copied FPGA wrapper RTL tree.
