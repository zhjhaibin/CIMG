@echo off
setlocal
title FFmpeg Photo Compressor

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compress-Photos.ps1" %*
set "compressExitCode=%ERRORLEVEL%"

echo.
if not "%compressExitCode%"=="0" echo The task finished with errors. See the messages above.
pause
exit /b %compressExitCode%

