#requires -Version 5.1
<#
.SYNOPSIS
    CIMG 一键安装脚本：下载最新版本、解压并加入用户 PATH。

.DESCRIPTION
    推荐用法（在 PowerShell 中复制运行一条命令即可安装）：

        irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1 | iex

    自定义安装目录：

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1))) -InstallDir "D:\Tools\CIMG"

    GitHub 访问不稳定时，可用镜像加速下载（例如）：

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1))) -DownloadMirror "https://ghfast.top"

    脚本可重复运行，会覆盖升级已安装的版本。

.EXAMPLE
    irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    # 安装目录；默认安装到当前用户的本地应用数据目录
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "CIMG"),

    # GitHub 仓库（owner/name），一般无需修改
    [string]$Repository = "zhjhaibin/CIMG",

    # 下载镜像前缀（如 https://ghfast.top），用于 GitHub 直连不稳定时加速；留空则直连
    [string]$DownloadMirror = ""
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 默认可能未启用 TLS 1.2，GitHub 需要
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# 带重试的网络请求
function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$MaxAttempts = 3,
        [string]$Description = ""
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $Action
        } catch {
            if ($attempt -eq $MaxAttempts) { throw }
            if ($Description) {
                Write-Host ("    第 {0} 次尝试失败，正在重试（{1}/{2}）..." -f $attempt, $attempt, ($MaxAttempts - 1)) -ForegroundColor DarkYellow
            }
            Start-Sleep -Seconds 2
        }
    }
}

# 获取最新版本及下载地址：优先 GitHub API，失败时回退到 releases/latest 重定向解析
function Get-LatestRelease {
    $releaseApiUrl = "https://api.github.com/repos/$Repository/releases/latest"
    try {
        $release = Invoke-WithRetry -Description "GitHub API" -Action {
            Invoke-RestMethod -Uri $releaseApiUrl -UseBasicParsing
        }
        if ($release.tag_name -and $release.assets) { return $release }
    } catch { }

    # 回退：releases/latest 会 302 到 /tag/<版本>，据此拼出下载地址（不依赖 API）
    try {
        Write-Host "    API 不可用，改用重定向方式解析最新版本..." -ForegroundColor DarkYellow
        $tag = Invoke-WithRetry -Description "版本重定向" -Action {
            $request = [Net.WebRequest]::Create("https://github.com/$Repository/releases/latest")
            $request.AllowAutoRedirect = $false
            $request.Timeout = 20000
            $response = $request.GetResponse()
            try {
                $location = $response.Headers["Location"]
            } finally {
                $response.Close()
            }
            if ($location -notmatch '/tag/(.+?)/?$') { throw "无法从重定向地址解析版本号：$location" }
            $Matches[1]
        }

        $assetName = "CIMG-" + $tag.TrimStart("v") + "-Windows-x64.zip"
        $downloadUrl = "https://github.com/$Repository/releases/download/$tag/" + $assetName
        return [pscustomobject]@{
            tag_name = $tag
            assets   = @([pscustomobject]@{ name = $assetName; browser_download_url = $downloadUrl })
        }
    } catch { }

    throw "无法连接 GitHub 获取版本信息。请检查网络后重试，或手动下载：https://github.com/$Repository/releases"
}

Write-Host ""
Write-Host "CIMG 安装程序" -ForegroundColor Green
Write-Host "    安装目录：$InstallDir"
Write-Host ""

# 1. 查询最新版本
Write-Step "正在查询最新版本"
$release = Get-LatestRelease
$version = $release.tag_name
$asset = $release.assets |
    Where-Object { $_.name -like "CIMG-*-Windows-x64.zip" } |
    Select-Object -First 1

if ($null -eq $asset) {
    throw "版本 $version 中没有找到 Windows 安装包（CIMG-*-Windows-x64.zip）。"
}

Write-Host "    最新版本：$version"

$alreadyInstalled = Test-Path -LiteralPath (Join-Path $InstallDir "cimg.exe") -PathType Leaf
if ($alreadyInstalled) {
    Write-Host "    检测到已安装的 CIMG，将覆盖升级。"
}

# 2. 下载
Write-Step ("正在下载 " + $asset.name)
$tempZip = Join-Path ([IO.Path]::GetTempPath()) $asset.name
$downloadUrl = $asset.browser_download_url
if ($DownloadMirror) {
    $downloadUrl = $DownloadMirror.TrimEnd("/") + "/" + $downloadUrl
    Write-Host "    使用镜像：$DownloadMirror"
}
Invoke-WithRetry -Description "下载" -MaxAttempts 3 -Action {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
}

# 3. 解压（直接用 .NET API，兼容 Windows PowerShell 5.1 与 PowerShell 7，支持覆盖升级）
Write-Step ("正在解压到 " + $InstallDir)
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
try {
    foreach ($entry in $zip.Entries) {
        $destinationPath = Join-Path $InstallDir $entry.FullName
        $destinationDir = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        if ($entry.Name) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationPath, $true)
        }
    }
} finally {
    $zip.Dispose()
}
Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath (Join-Path $InstallDir "cimg.exe") -PathType Leaf)) {
    throw "安装失败：解压后未找到 cimg.exe。"
}

# 4. 添加到当前用户 PATH（幂等）
Write-Step "正在添加到当前用户 PATH"
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($pathEntries -notcontains $InstallDir) {
    $newUserPath = (($pathEntries + $InstallDir) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Write-Host "    已添加：$InstallDir"
} else {
    Write-Host "    PATH 中已存在，跳过。"
}

# 5. 检查 FFmpeg（cimg 运行时依赖）
$ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffmpegBundled = Test-Path -LiteralPath (Join-Path $InstallDir "ffmpeg.exe") -PathType Leaf

if ($null -ne $ffmpegCommand -or $ffmpegBundled) {
    Write-Step "FFmpeg 检查通过"
} else {
    Write-Host "==> FFmpeg 检查" -ForegroundColor Yellow
    Write-Host "    未检测到 FFmpeg。运行 cimg 之前需要先安装：" -ForegroundColor Yellow
    Write-Host "      winget install Gyan.FFmpeg" -ForegroundColor Yellow
    Write-Host "    或者把 ffmpeg.exe 直接放到 $InstallDir 目录中。" -ForegroundColor Yellow
}

# 6. 完成
Write-Host ""
Write-Host "安装完成！" -ForegroundColor Green
Write-Host ""
Write-Host "请完全关闭并重新打开终端，然后在任意照片目录运行："
Write-Host ""
Write-Host "    cimg" -ForegroundColor White
Write-Host ""
Write-Host "当前窗口想立即使用的话，可以先运行："
Write-Host ""
Write-Host ('    $env:Path += ";' + $InstallDir + '"') -ForegroundColor White
Write-Host ""
Write-Host "卸载：运行 CIMG 目录中的 uninstall.ps1，或参考 README。" -ForegroundColor DarkGray
