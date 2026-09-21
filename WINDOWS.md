# Clipboard OCR for Windows

This port keeps the original clipboard-safe workflow and Markdown output, but replaces the macOS Swift/MLX layer with a high-DPI Windows desktop/tray app. PaddlePaddle CUDA performs layout detection and an official PaddleOCR-VL GGUF model runs through llama.cpp Vulkan on the NVIDIA GPU. The direct Paddle backend remains available as an automatic fallback.

## Supported machine

- Windows 10/11 x64
- NVIDIA GPU with compute capability 7.5, 8.0, 8.6, 8.9 or 12.0 (GTX 16 / RTX 20 / 30 / 40 / 50 series), and a current driver. RTX 4060 Laptop (8 GB, capability 8.9) is hardware-validated; other models still require real-device acceptance. CPU-only, AMD/Intel-only, Windows ARM64 and unlisted GPU architectures are not supported by this Windows runtime.
- About 15 GB free disk space for Python packages, caches, and models
- [uv](https://docs.astral.sh/uv/getting-started/installation/) and Windows Package Manager (`winget`) for source installation; the Release installer bundles the required setup tools

The tested machine is an RTX 4060 Laptop GPU with 8 GB VRAM and 32 GB system memory.

## Release installer

[Download v0.2.0 Preview 14](https://github.com/12chasse-neige/ClipboardOCR/releases/tag/v0.2.0-preview.14). The x64 web installer bundles pinned `uv` and llama.cpp runtimes, but downloads Paddle/CUDA packages and the official model during first setup. Allow about 15 GB free disk space and keep the machine online. The preview is not code-signed; compare its SHA-256 with the checksum attached to the GitHub Release. The installer now stops and records `setup.log` when dependencies or models fail, and keeps the failure window open. The managed Python interpreter, virtual environment and models are placed in `%LOCALAPPDATA%\ClipboardOCR`, so Steam/library mount points do not block setup. The installed app opens its main interface through the managed GUI interpreter with no console window. A lower-right notification appears when the model is ready; closing the UI keeps OCR in the tray, while **Quit** in the tray menu exits it.

Setup uses one **cu129** build for capabilities 7.5/8.0/8.6/8.9/12.0. All five architectures are present in the pinned Windows wheel; unknown or unsupported capabilities stop before large downloads. NVIDIA Windows driver **576.02 or newer** is required. This also avoids the cu126 wheel's inconsistent cuDNN declaration: it requests 9.5 but its binary reports compilation with 9.9. The cu129 build declares and uses cuDNN 9.9.0.52 consistently. The obsolete safetensors 0.6.2.dev0 workaround has been removed: PaddleOCR 3.7 / PaddleX 3.7.2 use safetensors 0.7.0. Setup checks the installed CUDA build as well as the package version, so upgrading an existing environment does not silently keep cu126.

The large Paddle wheel is downloaded from two official Paddle hosts, with partial-file resume and ZIP CRC validation before installation. CRC detects transfer corruption; it is not an independent publisher signature. Ordinary packages try Tsinghua TUNA, Tencent Cloud and PyPI, moving reachable sources first. Each source gets two install attempts, with uv's bounded HTTP retries, longer read timeout and two concurrent downloads. There is no guarantee of equal speed on every network.

Model transfer failures retry the official Hugging Face endpoint and then the community mirror, with two attempts per endpoint, two download workers and the pinned model revision. This handles file-transfer failures even when the API is reachable. Completed cache entries and recoverable model partials are reused; ordinary dependency wheels may need re-fetching after interruption. Setup prints a heartbeat and log location while child downloads run.

`CLIPBOARD_OCR_PYPI_INDEX=<index url>` forces one package index; `HF_ENDPOINT=<endpoint>` forces one model endpoint; `CLIPBOARD_OCR_DISABLE_MIRROR=1` disables community mirrors. `CLIPBOARD_OCR_PADDLE_INDEX=<index url>` is an advanced override and bypasses the default resumable Paddle downloader. Explicit source overrides are not silently replaced. Re-run **Complete Clipboard OCR Setup** after a failure; logs are under `%LOCALAPPDATA%\ClipboardOCR\logs`.

On hybrid laptops, llama.cpp explicitly selects the Vulkan adapter matching NVIDIA GPU 0 rather than assuming Vulkan and CUDA adapter order agree. Concurrency uses free VRAM at startup; a failed multi-slot server start retries with one slot. `CLIPBOARD_OCR_STARTUP_TIMEOUT=30..300` controls the server's per-attempt startup allowance (120 seconds by default). Only the real GPU kernel check and full OCR check establish that the particular machine works.

The installer targets the current user and needs no administrator access. Leave **Download the GPU runtime and models now** selected on its final page. Setup performs a real OCR smoke test before creating the desktop shortcut.

## Install from source

Open PowerShell in the project directory and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup.ps1
```

Setup installs the managed Python 3.12 interpreter, virtual environment and downloaded models under `%LOCALAPPDATA%\ClipboardOCR` (not an external uv interpreter). The selected application directory contains only static files and bundled tools, so Steam/library mount points cannot break uv's interpreter inspection. Setup also installs pinned application dependencies, llama.cpp, and a revision-pinned official PaddleOCR-VL GGUF model. Reruns reuse the environment and download cache instead of deleting them. The final check performs real end-to-end GPU OCR and creates `Clipboard OCR.lnk` on the desktop.

## Use

1. Double-click **Clipboard OCR** on the desktop. The control window opens and its icon appears in the notification area. The GPU engine warms in the background.
2. Copy an image or take a screenshot to the clipboard with `Win+Shift+S`.
3. Press `Ctrl+Alt+O`.
4. Wait for the **Markdown copied** notification and paste with `Ctrl+V`.

If the clipboard changes during recognition, the app preserves the newer clipboard. Right-click the tray icon and choose **Copy OCR Result** to copy the pending result explicitly.

Model loading happens when the app starts, so recognition is warm before the first shortcut. The engine selects one llama.cpp slot below 7,000 MiB available VRAM, two from 7,000 MiB, three from 11,000 MiB, or four from 15,000 MiB. Set `CLIPBOARD_OCR_CONCURRENCY=1..4` before launch to override it. On the tested 8 GB RTX 4060, the verified 443-character English formula page took 2.6-3.4 seconds on its first recognition and 0.8-0.9 seconds warm. One slot took 3.471/1.240 seconds; four slots took 33.474/0.686 seconds because first-use GPU initialization overwhelmed the small card. These are fixture measurements for the two-slot 8 GB tier, not validation of the other tiers or a general latency guarantee. **Release GPU** stops both model stages and clears GPU memory. Recognition does not require Internet after setup and does not save OCR history.

Long results are copied with explicitly typed 64-bit Win32 global-memory handles. The regression test covers a multi-megabyte Unicode payload; the previous `int too long to convert` failure was a clipboard-handle bug, not an OCR character limit.

Clipboard images above 12 megapixels are downsampled once with Lanczos filtering and transparent input is composited on white. This bounds memory and latency while leaving ordinary 4K screenshots unchanged. Unexpected backend failures no longer terminate the worker silently: the engine is released, the UI offers a reload, and private diagnostic logs rotate under `%LOCALAPPDATA%\ClipboardOCR\logs` without recording images or OCR text. A crashed llama.cpp child is restarted once automatically.
