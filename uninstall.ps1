#requires -Version 5.1
<#
.SYNOPSIS
    CIMG 卸载脚本：从用户 PATH 移除并删除安装目录。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File uninstall.ps1

    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -InstallDir "D:\Tools\CIMG"
#>
[CmdletBinding()]
param(
    # 安装目录；需与安装时一致
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "CIMG")
)

$ErrorActionPreference = "Stop"
$InstallDir = [IO.Path]::GetFullPath($InstallDir)

Write-Host ""
Write-Host "CIMG 卸载程序" -ForegroundColor Green
Write-Host "    安装目录：$InstallDir"
Write-Host ""

# 1. 从当前用户 PATH 中移除
Write-Host "==> 正在从用户 PATH 移除" -ForegroundColor Cyan
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$kept = @($pathEntries | Where-Object {
    [IO.Path]::GetFullPath($_).TrimEnd('\') -ne $InstallDir.TrimEnd('\')
})

if ($kept.Count -lt $pathEntries.Count) {
    [Environment]::SetEnvironmentVariable("Path", ($kept -join ";"), "User")
    Write-Host "    已移除：$InstallDir"
} else {
    Write-Host "    PATH 中未找到该目录，跳过。"
}

# 2. 删除安装目录
if (Test-Path -LiteralPath $InstallDir) {
    Write-Host "==> 正在删除安装目录" -ForegroundColor Cyan
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "    已删除。"
} else {
    Write-Host "==> 安装目录不存在，跳过删除" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "卸载完成。重新打开终端后 cimg 命令将不再可用。" -ForegroundColor Green
Write-Host ""
