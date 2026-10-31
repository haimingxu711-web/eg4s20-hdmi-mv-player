@echo off
rem Double-click      = JTAG download to SRAM (lost on power-off)
rem burn.bat flash   = program SPI flash (kept after power-off)
set MODE=%1
if "%MODE%"=="" set MODE=jtag
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0burn.ps1" -Mode %MODE%
if "%2"=="" pause
