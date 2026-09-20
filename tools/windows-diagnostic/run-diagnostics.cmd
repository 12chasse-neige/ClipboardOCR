@echo off
setlocal
title Clipboard OCR Windows Diagnostic
powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect-diagnostics.ps1"
echo.
echo 诊断窗口会保持打开。请把生成的 ClipboardOCR-diagnostic-*.zip 发回。
