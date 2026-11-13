<#
.SYNOPSIS
    CIMG one-command installer: downloads the latest release, extracts it
    and adds it to the current user PATH.

.DESCRIPTION
    Recommended usage (copy-paste a single line in PowerShell):

        irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1 | iex

    Custom install directory:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1))) -InstallDir "D:\Tools\CIMG"

    Mirror acceleration when GitHub is slow or unreachable:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1))) -DownloadMirror "https://ghfast.top"

    Re-running the script upgrades the existing installation in place.
#>
[CmdletBinding()]
param(
    # Installation directory; defaults to the per-user local app data folder.
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "CIMG"),

    # GitHub repository (owner/name). Normally no need to change.
    [string]$Repository = "zhjhaibin/CIMG",

    # Download mirror prefix (e.g. https://ghfast.top) used when GitHub direct
    # downloads are unstable. Leave empty for direct download.
    [string]$DownloadMirror = ""
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 may not enable TLS 1.2 by default; GitHub requires it.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# Network request with retries.
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
                Write-Host ("    Attempt {0} failed, retrying ({1}/{2})..." -f $attempt, $attempt, ($MaxAttempts - 1)) -ForegroundColor DarkYellow
            }
            Start-Sleep -Seconds 2
        }
    }
}

# Get the latest release: prefer the GitHub API, fall back to parsing the
# releases/latest redirect (works without API access).
function Get-LatestRelease {
    $releaseApiUrl = "https://api.github.com/repos/$Repository/releases/latest"
    try {
        $release = Invoke-WithRetry -Description "GitHub API" -Action {
            Invoke-RestMethod -Uri $releaseApiUrl -UseBasicParsing
        }
        if ($release.tag_name -and $release.assets) { return $release }
    } catch { }

    # Fallback: releases/latest 302-redirects to /tag/<version>; build the
    # download URL from that tag without touching the API.
    try {
        Write-Host "    API unavailable, resolving latest version via redirect..." -ForegroundColor DarkYellow
        $tag = Invoke-WithRetry -Description "version redirect" -Action {
            $request = [Net.WebRequest]::Create("https://github.com/$Repository/releases/latest")
            $request.AllowAutoRedirect = $false
            $request.Timeout = 20000
            $response = $request.GetResponse()
            try {
                $location = $response.Headers["Location"]
            } finally {
                $response.Close()
            }
            if ($location -notmatch '/tag/(.+?)/?$') { throw "Cannot parse version from redirect: $location" }
            $Matches[1]
        }

        $assetName = "CIMG-" + $tag.TrimStart("v") + "-Windows-x64.zip"
        $downloadUrl = "https://github.com/$Repository/releases/download/$tag/" + $assetName
        return [pscustomobject]@{
            tag_name = $tag
            assets   = @([pscustomobject]@{ name = $assetName; browser_download_url = $downloadUrl })
        }
    } catch { }

    throw "Cannot reach GitHub to resolve the latest version. Check your network and retry, or download manually from: https://github.com/$Repository/releases"
}

Write-Host ""
Write-Host "CIMG installer" -ForegroundColor Green
Write-Host "    Install directory: $InstallDir"
Write-Host ""

# 1. Resolve the latest version.
Write-Step "Resolving latest version"
$release = Get-LatestRelease
$version = $release.tag_name
$asset = $release.assets |
    Where-Object { $_.name -like "CIMG-*-Windows-x64.zip" } |
    Select-Object -First 1

if ($null -eq $asset) {
    throw "Release $version does not contain a Windows package (CIMG-*-Windows-x64.zip)."
}

Write-Host "    Latest version: $version"

$alreadyInstalled = Test-Path -LiteralPath (Join-Path $InstallDir "cimg.exe") -PathType Leaf
if ($alreadyInstalled) {
    Write-Host "    Existing installation detected; upgrading in place."
}

# 2. Download.
Write-Step ("Downloading " + $asset.name)
$tempZip = Join-Path ([IO.Path]::GetTempPath()) $asset.name
$downloadUrl = $asset.browser_download_url
if ($DownloadMirror) {
    $downloadUrl = $DownloadMirror.TrimEnd("/") + "/" + $downloadUrl
    Write-Host "    Using mirror: $DownloadMirror"
}
Invoke-WithRetry -Description "download" -MaxAttempts 3 -Action {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
}

# 3. Extract using the .NET API directly (works on both Windows PowerShell 5.1
#    and PowerShell 7, and overwrites files so re-running upgrades in place).
Write-Step ("Extracting to " + $InstallDir)
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
    throw "Installation failed: cimg.exe not found after extraction."
}

# 4. Add to the current user PATH (idempotent).
Write-Step "Adding to current user PATH"
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($pathEntries -notcontains $InstallDir) {
    $newUserPath = (($pathEntries + $InstallDir) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Write-Host "    Added: $InstallDir"
} else {
    Write-Host "    Already present in PATH; skipped."
}

# 5. Check FFmpeg (required by cimg at runtime).
$ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffmpegBundled = Test-Path -LiteralPath (Join-Path $InstallDir "ffmpeg.exe") -PathType Leaf

if ($null -ne $ffmpegCommand -or $ffmpegBundled) {
    Write-Step "FFmpeg check passed"
} else {
    Write-Host "==> FFmpeg check" -ForegroundColor Yellow
    Write-Host "    FFmpeg was not detected. cimg needs it to compress images:" -ForegroundColor Yellow
    Write-Host "      winget install Gyan.FFmpeg" -ForegroundColor Yellow
    Write-Host "    Or place ffmpeg.exe directly into $InstallDir." -ForegroundColor Yellow
}

# 6. Done.
Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Fully close and reopen your terminal, then run in any photo folder:"
Write-Host ""
Write-Host "    cimg" -ForegroundColor White
Write-Host ""
Write-Host "To use it in the current window right away, run first:"
Write-Host ""
Write-Host ('    $env:Path += ";' + $InstallDir + '"') -ForegroundColor White
Write-Host ""
Write-Host "Uninstall: run uninstall.ps1 next to cimg.exe in the install directory." -ForegroundColor DarkGray
