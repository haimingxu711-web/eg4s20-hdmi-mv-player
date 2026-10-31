@echo off
rem 命令行构建：综合 + 布局布线 + 生成比特流（约 10 分钟）
rem TD 安装路径不同时修改下一行
set TD=D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe
cd /d "%~dp0..\src\td_my"
"%TD%" build.tcl < nul > build.log 2>&1
findstr /i /c:"ERROR" build.log
dir /s /b my_top_Runs\phy_1\*.bit
if "%1"=="" pause
