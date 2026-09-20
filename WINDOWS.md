# Clipboard OCR for Windows

This port keeps the original clipboard-safe workflow and Markdown output, but replaces the macOS Swift/MLX layer with a high-DPI Windows desktop/tray app. PaddlePaddle CUDA performs layout detection and an official PaddleOCR-VL GGUF model runs through llama.cpp Vulkan on the NVIDIA GPU. The direct Paddle backend remains available as an automatic fallback.

## Supported machine

- Windows 10/11 x64
- NVIDIA GPU with a current driver. RTX 4060 Laptop (8 GB, compute capability 8.9) is the validated configuration; other GPUs are not yet qualified.
- About 10 GB free disk space for Python packages, caches, and models
- [uv](https://docs.astral.sh/uv/getting-started/installation/) and Windows Package Manager (`winget`)

The tested machine is an RTX 4060 Laptop GPU with 8 GB VRAM and 32 GB system memory.

## Install

Open PowerShell in the project directory and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup.ps1
```

Setup installs a self-contained Python 3.12 runtime under `.windows` (not an external uv interpreter), pinned application dependencies, llama.cpp, and a revision-pinned official PaddleOCR-VL GGUF model. Reruns reuse the environment and download cache instead of deleting them. The final check performs real end-to-end GPU OCR and creates `Clipboard OCR.lnk` on the desktop.

## Use

1. Double-click **Clipboard OCR** on the desktop. The control window opens and its icon appears in the notification area. The GPU engine warms in the background.
2. Copy an image or take a screenshot to the clipboard with `Win+Shift+S`.
3. Press `Ctrl+Alt+O`.
4. Wait for the **Markdown copied** notification and paste with `Ctrl+V`.

If the clipboard changes during recognition, the app preserves the newer clipboard. Right-click the tray icon and choose **Copy OCR Result** to copy the pending result explicitly.

Model loading happens when the app starts, so recognition is warm before the first shortcut. Independent document regions use two bounded llama.cpp inference slots. On the tested RTX 4060 machine, the verified 443-character English formula page took 2.6-3.4 seconds on its first recognition and 0.8-0.9 seconds warm. One slot took 3.471/1.240 seconds; four slots took 33.474/0.686 seconds because first-use GPU initialization overwhelmed the small card. Two slots are therefore the measured default, not a theoretical maximum. These are fixture measurements, not general latency guarantees. Set `CLIPBOARD_OCR_CONCURRENCY=1..4` before launch to override it. **Release GPU** stops both model stages and clears GPU memory. Recognition does not require Internet after setup and does not save OCR history.

Long results are copied with explicitly typed 64-bit Win32 global-memory handles. The regression test covers a multi-megabyte Unicode payload; the previous `int too long to convert` failure was a clipboard-handle bug, not an OCR character limit.

Clipboard images above 12 megapixels are downsampled once with Lanczos filtering and transparent input is composited on white. This bounds memory and latency while leaving ordinary 4K screenshots unchanged. Unexpected backend failures no longer terminate the worker silently: the engine is released, the UI offers a reload, and private diagnostic logs rotate under `%LOCALAPPDATA%\ClipboardOCR\logs` without recording images or OCR text. A crashed llama.cpp child is restarted once automatically.
