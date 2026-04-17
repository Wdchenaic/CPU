@echo off
setlocal
set SCRIPT_DIR=%~dp0
set PART=%1
set TOP=%2
if "%PART%"=="" set PART=xc7z020clg400-1
if "%TOP%"=="" set TOP=panda_risc_v
vivado -mode batch -source "%SCRIPT_DIR%scripts\run_core_quick_synth.tcl" -tclargs %PART% %TOP%
endlocal
