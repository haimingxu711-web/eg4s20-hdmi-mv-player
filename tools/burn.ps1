# 一键烧录安路 FPGA (EG4S20BG256)
# 用法: burn.ps1 [-Mode jtag|flash] [-Bit <path\to\xxx.bit>]
#   jtag  : 下载到 SRAM，快，断电丢失（默认）
#   flash : 写入板载 SPI Flash，断电保留
param(
    [ValidateSet('jtag', 'flash')]
    [string]$Mode = 'jtag',
    [string]$Bit
)

$ErrorActionPreference = 'Stop'
$TdBin = 'D:\Anlogic\TD6.2.1\bin\bw_commands_prompt.exe'

if (-not (Test-Path $TdBin)) {
    Write-Host "找不到 TD 下载工具: $TdBin" -ForegroundColor Red
    exit 1
}

# 未指定 bit 时，取脚本所在目录下最新生成的 .bit
if (-not $Bit) {
    # 仓库内最新的 .bit（自己编译的 my_top_Runs 或 release/）
    $found = Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Recurse -Filter *.bit -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) {
        Write-Host "没找到 .bit 文件，请先在 TD 里跑完 Generate Bitstream。" -ForegroundColor Red
        exit 1
    }
    $Bit = $found.FullName
}
$Bit = (Resolve-Path $Bit).Path

# 参数与 TD 图形界面下载时记录在日志里的命令一致
if ($Mode -eq 'jtag') {
    $cmd = 'download -bit "{0}" -mode jtag -spd 7 -sec 64 -cable 0'
} else {
    $cmd = 'download -bit "{0}" -mode program_spi -v -spd 8 -sec 64 -cable 0 -flashsize 128'
}
$cmd = $cmd -f ($Bit -replace '\\', '/')

$item = Get-Item $Bit
Write-Host "bit 文件 : $Bit"
Write-Host "生成时间 : $($item.LastWriteTime)"
Write-Host "下载模式 : $Mode"
Write-Host ''

$tmp = Join-Path $env:TEMP 'anlogic_burn'
New-Item -ItemType Directory -Force $tmp | Out-Null
$tcl = Join-Path $tmp 'burn.tcl'
Set-Content -Path $tcl -Value "$cmd`nexit" -Encoding ascii

Push-Location $tmp
try {
    $out = & $TdBin 'burn.tcl' 2>&1 | ForEach-Object { "$_" }
} finally {
    Pop-Location
}
$out | Where-Object { $_ -match 'PRG-|ERROR|WARNING|finish command|couldn''t|invalid' } | ForEach-Object { Write-Host $_ }

Write-Host ''
if (($out -match 'ERROR|couldn''t|invalid command') -or -not ($out -match 'finish command')) {
    Write-Host '烧录失败。检查：下载器驱动、USB 线、开发板是否上电；TD 的 Download 窗口是否正占用下载器。' -ForegroundColor Red
    exit 1
}
Write-Host '烧录成功。' -ForegroundColor Green
