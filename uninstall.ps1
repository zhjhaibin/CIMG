<#
.SYNOPSIS
    CIMG uninstaller: removes the install directory from the user PATH and deletes it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File uninstall.ps1

    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -InstallDir "D:\Tools\CIMG"
#>
[CmdletBinding()]
param(
    # Installation directory; must match the one used at install time.
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "CIMG")
)

$ErrorActionPreference = "Stop"
$InstallDir = [IO.Path]::GetFullPath($InstallDir)

Write-Host ""
Write-Host "CIMG uninstaller" -ForegroundColor Green
Write-Host "    Install directory: $InstallDir"
Write-Host ""

# 1. Remove from the current user PATH.
Write-Host "==> Removing from user PATH" -ForegroundColor Cyan
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$kept = @($pathEntries | Where-Object {
    [IO.Path]::GetFullPath($_).TrimEnd('\') -ne $InstallDir.TrimEnd('\')
})

if ($kept.Count -lt $pathEntries.Count) {
    [Environment]::SetEnvironmentVariable("Path", ($kept -join ";"), "User")
    Write-Host "    Removed: $InstallDir"
} else {
    Write-Host "    Directory not found in PATH; skipped."
}

# 2. Delete the installation directory.
if (Test-Path -LiteralPath $InstallDir) {
    Write-Host "==> Deleting installation directory" -ForegroundColor Cyan
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "    Deleted."
} else {
    Write-Host "==> Installation directory does not exist; skipped" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Uninstall complete. The cimg command will no longer work after reopening the terminal." -ForegroundColor Green
Write-Host ""
