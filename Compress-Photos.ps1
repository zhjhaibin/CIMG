[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$InputPath,

    [ValidateRange(0, 32768)]
    [int]$MaxLongEdge = 1920,

    [ValidateSet("same", "jpg", "webp")]
    [string]$OutputFormat = "same",

    [ValidateRange(1, 100)]
    [int]$Quality = 80,

    [ValidateRange(0, 1048576)]
    [int]$MinSizeKB = 400,

    [ValidateNotNullOrEmpty()]
    [string]$OutputFolderName = "_compressed",

    [switch]$Cover,

    [switch]$Overwrite
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$supportedExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff")

function Find-Ffmpeg {
    $bundledFfmpeg = Join-Path $PSScriptRoot "ffmpeg.exe"
    if (Test-Path -LiteralPath $bundledFfmpeg -PathType Leaf) {
        return $bundledFfmpeg
    }

    $command = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "ffmpeg was not found. Install it or put ffmpeg.exe next to this script."
}

function Select-InputFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select a photo folder"
    $dialog.ShowNewFolderButton = $false

    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    }
    finally {
        $dialog.Dispose()
    }

    return $null
}

function Get-OutputExtension {
    param(
        [string]$SourceExtension,
        [string]$RequestedFormat
    )

    if ($RequestedFormat -eq "same") {
        return $SourceExtension.ToLowerInvariant()
    }

    return "." + $RequestedFormat
}

function Get-CodecArguments {
    param(
        [string]$Extension,
        [int]$RequestedQuality
    )

    switch ($Extension.ToLowerInvariant()) {
        ".jpg" {
            $qScale = [Math]::Max(2, [Math]::Min(20, [Math]::Round(2 + ((100 - $RequestedQuality) / 8.0))))
            return @("-q:v", [string]$qScale)
        }
        ".jpeg" {
            $qScale = [Math]::Max(2, [Math]::Min(20, [Math]::Round(2 + ((100 - $RequestedQuality) / 8.0))))
            return @("-q:v", [string]$qScale)
        }
        ".png" {
            return @("-compression_level", "9", "-pred", "mixed")
        }
        ".webp" {
            return @("-quality", [string]$RequestedQuality, "-compression_level", "6")
        }
        ".tif" {
            return @("-compression_algo", "deflate")
        }
        ".tiff" {
            return @("-compression_algo", "deflate")
        }
        default {
            return @()
        }
    }
}

function Get-UniqueTargetPath {
    param(
        [string]$CandidatePath,
        [string]$SourceExtension,
        [System.Collections.Generic.HashSet[string]]$ReservedTargets
    )

    if ($ReservedTargets.Add($CandidatePath)) {
        return $CandidatePath
    }

    $directory = Split-Path -Parent $CandidatePath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($CandidatePath)
    $extension = [System.IO.Path]::GetExtension($CandidatePath)
    $sourceSuffix = $SourceExtension.TrimStart(".")
    $number = 1

    do {
        $suffix = if ($number -eq 1) { "_from_$sourceSuffix" } else { "_from_${sourceSuffix}_$number" }
        $nextCandidate = Join-Path $directory ($name + $suffix + $extension)
        $number++
    } while (-not $ReservedTargets.Add($nextCandidate))

    return $nextCandidate
}

function Get-InputJobs {
    param(
        [string[]]$Paths,
        [string]$OutputFolder,
        [string]$RequestedFormat,
        [bool]$CoverSource
    )

    $seenSources = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    $reservedTargets = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    $jobs = New-Object System.Collections.Generic.List[object]

    foreach ($rawPath in $Paths) {
        if (-not (Test-Path -LiteralPath $rawPath)) {
            Write-Warning "Not found: $rawPath"
            continue
        }

        $item = Get-Item -LiteralPath $rawPath
        if ($item.PSIsContainer) {
            $root = $item.FullName.TrimEnd("\", "/")
            $outputRoot = Join-Path $root $OutputFolder
            $files = Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
                $extension = $_.Extension.ToLowerInvariant()
                $isSupported = $supportedExtensions -contains $extension
                $isOutput = $_.FullName.StartsWith($outputRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
                $isSupported -and -not $isOutput
            }

            foreach ($file in $files) {
                if (-not $seenSources.Add($file.FullName)) {
                    continue
                }

                $outputExtension = Get-OutputExtension -SourceExtension $file.Extension -RequestedFormat $RequestedFormat
                if ($CoverSource) {
                    $target = $file.FullName
                }
                else {
                    $relativePath = $file.FullName.Substring($root.Length).TrimStart("\", "/")
                    $relativeDirectory = Split-Path -Parent $relativePath
                    $outputName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + $outputExtension
                    $targetDirectory = if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
                        $outputRoot
                    }
                    else {
                        Join-Path $outputRoot $relativeDirectory
                    }
                    $target = Join-Path $targetDirectory $outputName
                }
                $target = Get-UniqueTargetPath -CandidatePath $target -SourceExtension $file.Extension -ReservedTargets $reservedTargets
                $jobs.Add([PSCustomObject]@{ Source = $file.FullName; Target = $target; OutputExtension = $outputExtension })
            }
        }
        else {
            $extension = $item.Extension.ToLowerInvariant()
            if ($supportedExtensions -notcontains $extension) {
                Write-Warning "Unsupported image type: $($item.FullName)"
                continue
            }
            if (-not $seenSources.Add($item.FullName)) {
                continue
            }

            $outputRoot = Join-Path $item.DirectoryName $OutputFolder
            $outputExtension = Get-OutputExtension -SourceExtension $item.Extension -RequestedFormat $RequestedFormat
            if ($CoverSource) {
                $target = $item.FullName
            }
            else {
                $outputName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name) + $outputExtension
                $target = Join-Path $outputRoot $outputName
            }
            $target = Get-UniqueTargetPath -CandidatePath $target -SourceExtension $item.Extension -ReservedTargets $reservedTargets
            $jobs.Add([PSCustomObject]@{ Source = $item.FullName; Target = $target; OutputExtension = $outputExtension })
        }
    }

    return $jobs
}

function Replace-SourceFile {
    param(
        [string]$TemporaryPath,
        [string]$SourcePath
    )

    $sourceDirectory = Split-Path -Parent $SourcePath
    $sourceName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $sourceExtension = [System.IO.Path]::GetExtension($SourcePath)
    $backupName = $sourceName + ".backup-" + [Guid]::NewGuid().ToString("N") + $sourceExtension
    $backupPath = Join-Path $sourceDirectory $backupName

    Move-Item -LiteralPath $SourcePath -Destination $backupPath
    try {
        Move-Item -LiteralPath $TemporaryPath -Destination $SourcePath
    }
    catch {
        if (-not (Test-Path -LiteralPath $SourcePath) -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $SourcePath
        }
        throw
    }

    Remove-Item -LiteralPath $backupPath -Force
}

try {
    $ffmpeg = Find-Ffmpeg

    if ($null -eq $InputPath -or $InputPath.Count -eq 0) {
        $selectedFolder = Select-InputFolder
        if ([string]::IsNullOrWhiteSpace($selectedFolder)) {
            Write-Host "Cancelled."
            exit 0
        }
        $InputPath = @($selectedFolder)
    }

    if ($Cover -and $OutputFormat -ne "same") {
        throw "-Cover can only be used with -OutputFormat same."
    }

    $jobs = @(Get-InputJobs -Paths $InputPath -OutputFolder $OutputFolderName -RequestedFormat $OutputFormat -CoverSource $Cover)
    if ($jobs.Count -eq 0) {
        Write-Host "No supported images found."
        exit 0
    }

    $successCount = 0
    $skippedCount = 0
    $failedCount = 0
    [long]$processedSourceBytes = 0
    [long]$outputBytes = 0

    Write-Host "Found $($jobs.Count) image(s)."

    for ($index = 0; $index -lt $jobs.Count; $index++) {
        $job = $jobs[$index]
        $sourceFile = Get-Item -LiteralPath $job.Source
        $progress = [Math]::Round((($index + 1) / $jobs.Count) * 100)
        Write-Progress -Activity "Compressing photos" -Status "$($index + 1)/$($jobs.Count): $($sourceFile.Name)" -PercentComplete $progress

        if (-not $Cover -and (Test-Path -LiteralPath $job.Target) -and -not $Overwrite) {
            $processedSourceBytes += $sourceFile.Length
            $outputBytes += (Get-Item -LiteralPath $job.Target).Length
            $skippedCount++
            Write-Host "SKIP  $($sourceFile.Name) (output exists)"
            continue
        }

        $targetDirectory = Split-Path -Parent $job.Target
        [void](New-Item -ItemType Directory -Path $targetDirectory -Force)

        if ($OutputFormat -eq "same" -and $MinSizeKB -gt 0 -and $sourceFile.Length -lt ($MinSizeKB * 1KB)) {
            if (-not $Cover) {
                Copy-Item -LiteralPath $sourceFile.FullName -Destination $job.Target -Force
                $outputFile = Get-Item -LiteralPath $job.Target
                $outputFile.LastWriteTime = $sourceFile.LastWriteTime
            }
            $processedSourceBytes += $sourceFile.Length
            $outputBytes += $sourceFile.Length
            $skippedCount++
            $smallFileAction = if ($Cover) { "SKIP" } else { "COPY" }
            Write-Host "$smallFileAction  $($sourceFile.Name) (smaller than $MinSizeKB KB)"
            continue
        }

        $temporaryName = [System.IO.Path]::GetFileNameWithoutExtension($job.Target) + ".tmp-" + [Guid]::NewGuid().ToString("N") + $job.OutputExtension
        $temporaryPath = Join-Path $targetDirectory $temporaryName

        $ffmpegArguments = @("-hide_banner", "-loglevel", "error", "-y", "-i", $sourceFile.FullName)
        if ($MaxLongEdge -gt 0) {
            $scaleFilter = "scale=w='if(gt(max(iw,ih),$MaxLongEdge),if(gte(iw,ih),$MaxLongEdge,-2),iw)':h='if(gt(max(iw,ih),$MaxLongEdge),if(gte(iw,ih),-2,$MaxLongEdge),ih)':flags=lanczos"
            $ffmpegArguments += @("-vf", $scaleFilter)
        }
        $ffmpegArguments += @("-map_metadata", "0", "-frames:v", "1", "-update", "1")
        $ffmpegArguments += Get-CodecArguments -Extension $job.OutputExtension -RequestedQuality $Quality
        $ffmpegArguments += $temporaryPath

        try {
            & $ffmpeg @ffmpegArguments
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryPath)) {
                throw "ffmpeg exited with code $LASTEXITCODE"
            }

            $temporaryFile = Get-Item -LiteralPath $temporaryPath
            $recordAsCompressed = $true
            if ($OutputFormat -eq "same" -and $temporaryFile.Length -ge $sourceFile.Length) {
                Remove-Item -LiteralPath $temporaryPath -Force
                if ($Cover) {
                    $recordAsCompressed = $false
                    Write-Host "SKIP  $($sourceFile.Name) (re-encoding was not smaller)"
                }
                else {
                    Copy-Item -LiteralPath $sourceFile.FullName -Destination $job.Target -Force
                    Write-Host "COPY  $($sourceFile.Name) (re-encoding was not smaller)"
                }
            }
            else {
                if ($Cover) {
                    Replace-SourceFile -TemporaryPath $temporaryPath -SourcePath $sourceFile.FullName
                    Write-Host "COVER $($sourceFile.Name)"
                }
                else {
                    Move-Item -LiteralPath $temporaryPath -Destination $job.Target -Force
                    Write-Host "OK    $($sourceFile.Name)"
                }
            }

            $outputFile = Get-Item -LiteralPath $job.Target
            $outputFile.LastWriteTime = $sourceFile.LastWriteTime
            $processedSourceBytes += $sourceFile.Length
            $outputBytes += $outputFile.Length
            if ($recordAsCompressed) {
                $successCount++
            }
            else {
                $skippedCount++
            }
        }
        catch {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
            $failedCount++
            Write-Warning "FAILED $($sourceFile.FullName): $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "Compressing photos" -Completed
    $savedBytes = [Math]::Max([long]0, [long]($processedSourceBytes - $outputBytes))
    $savedPercent = if ($processedSourceBytes -gt 0) { [Math]::Round(($savedBytes / $processedSourceBytes) * 100, 1) } else { 0 }
    $sourceMB = [Math]::Round($processedSourceBytes / 1MB, 1)
    $outputMB = [Math]::Round($outputBytes / 1MB, 1)
    $savedMB = [Math]::Round($savedBytes / 1MB, 1)

    Write-Host ""
    Write-Host "Done: $successCount compressed, $skippedCount skipped, $failedCount failed."
    Write-Host "Size: $sourceMB MB -> $outputMB MB (saved $savedMB MB, $savedPercent%)."

    if ($failedCount -gt 0) {
        exit 2
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
