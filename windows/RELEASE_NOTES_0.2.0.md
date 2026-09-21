# Clipboard OCR v0.2.0 Preview 14

Windows installation reliability and device compatibility update from `feature/Windows`.

## Download

Use **ClipboardOCR-0.2.0-preview.14-windows-x64-setup.exe**. Compare its SHA-256 with **SHA256SUMS.txt**. This is an unsigned web installer; the GPU runtime and models still require a first-run download. Allow about 15 GB free disk space including caches. Existing model and package caches are reused.

## Fixed

- PyPI mirror priority: install from one selected source at a time, with bounded retries and real failure-driven failover. The former extra-index setting silently preferred official PyPI over the measured mirror.
- Paddle wheel downloads: two official hosts, partial-file resume, visible byte progress and ZIP CRC validation before installation. Failed partial downloads survive setup restarts.
- Model downloads: retry and switch endpoint after file-transfer failures, not only after an API reachability probe. Explicit endpoint overrides and the no-community-mirror option are respected.
- RTX 50 dependency conflict: removed the obsolete safetensors 0.6.2.dev0 workaround. PaddleOCR 3.7.0 / PaddleX 3.7.2 resolve together with safetensors 0.7.0.
- CUDA dependency consistency: use the cu129 wheel for all five supported architectures. The old cu126 wheel declares cuDNN 9.5 but warns at runtime that it was compiled with 9.9; the unified cu129 build declares and uses 9.9.0.52 consistently. Verify the complete dependency graph after installation.
- Device changes: inspect the installed CUDA build, so an existing Paddle 3.2.1 cu126 environment is not mistaken for cu129 just because the version number matches.
- GPU detection uses locale-independent parsing and stops clearly on failed detection, unsupported architecture or an outdated driver before downloading the large runtime.
- Hybrid laptops: select the Vulkan adapter matching NVIDIA GPU 0. Concurrency uses available VRAM; a failed multi-slot server start retries with one slot.
- Setup GPU verification explicitly selects `gpu:0`, runs a real GPU operation, then checks full OCR. It no longer attributes every CUDA failure solely to missing architecture kernels.

## Device coverage and limits

| Windows wheel | Compiled GPU capabilities | cuDNN dependency |
|---|---|---|
| Paddle 3.2.1 cu129 / Python 3.12 x64 | 7.5, 8.0, 8.6, 8.9, 12.0 (GTX 16 / RTX 20 / 30 / 40 / 50 families) | 9.9.0.52 |

**NVIDIA Windows driver 576.02 or newer is required on all supported GPUs.** Older drivers must be updated before setup. There is no separately maintained legacy CUDA 11/12.6 installation path.

These are the pinned wheel's build metadata and setup policies, not hardware qualification for every card. **RTX 50 hardware was not available for a real-device OCR test.** CPU-only, AMD/Intel-only, Windows ARM64 and architectures not listed above are not supported by this Windows runtime. NVIDIA GPU 0 is used; arbitrary multi-GPU scheduling is not provided.

The macOS v0.1.0 baseline remains unchanged. This release supplies a Windows installer; source archives still include both platforms.

## Validation

The accompanying `VALIDATION-preview.14.md` records exact checks and limitations. Network download success on this machine cannot guarantee speed or availability on every user's network.

If setup fails, rerun **Complete Clipboard OCR Setup**. Logs are under `%LOCALAPPDATA%\ClipboardOCR\logs`. Do not delete the runtime/model caches as a first troubleshooting step.
