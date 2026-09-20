@echo off
setlocal
title Clipboard OCR Windows Diagnostic
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect-diagnostics.ps1"
echo.
echo 诊断完成后，请把生成的 ClipboardOCR-diagnostic-*.zip 发回。
pause
