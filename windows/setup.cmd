@echo off
setlocal
cd /d "%~dp0.."
title Clipboard OCR setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo Clipboard OCR setup failed with exit code %RC%.
    echo Read the full log at: %LOCALAPPDATA%\ClipboardOCR\logs\setup.log
    echo This window will remain open so the error is not lost.
    pause
)
exit /b %RC%
