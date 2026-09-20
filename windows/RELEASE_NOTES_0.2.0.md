# Clipboard OCR v0.2.0 Preview 8

Updated downloadable Windows installer built from `feature/Windows`. This is a **web installer**, not a complete offline bundle: it includes pinned setup tools and downloads about 6 GB of GPU runtime and model data during first setup. The managed Python interpreter is installed under `%LOCALAPPDATA%\ClipboardOCR\python`, avoiding the untrusted-mount-point failure seen when the app is extracted under `D:\Steam\test`.

## Validated configuration

- Windows 11 Home x64, build 26200
- NVIDIA GeForce RTX 4060 Laptop GPU, 8 GB VRAM
- PaddlePaddle GPU 3.2.1 / CUDA 12.6 / cuDNN 9.9.0.52
- PaddleOCR 3.7.0 / PaddleOCR-VL 1.6
- llama.cpp b11026, two automatically selected Vulkan inference slots

## Included

- High-DPI desktop and tray interface with `Ctrl+Alt+O` global OCR shortcut
- Opens the main interface immediately; closing it returns the app to the tray instead of exiting
- Console-free desktop launch through the managed GUI `pythonw.exe`; backend processes also use no-window creation flags
- Lower-right readiness notification after the OCR model has finished loading
- Local image-to-Markdown recognition for prose, equations and document layout
- Clipboard change protection and 64-bit multi-megabyte Unicode output
- Bounded preprocessing for inputs above 12 megapixels
- Automatic one-time recovery when the llama.cpp service crashes
- Rotating local diagnostics that do not record images or recognized text
- Idempotent source/runtime setup and revision-pinned GGUF model download
- Setup now stops on dependency/model/GPU verification failures and writes `setup.log` instead of creating a broken shortcut
- Setup failures keep a visible diagnostic window open instead of closing immediately
- Conservative VRAM-based selection of one to four inference slots, with an explicit environment override

## Verification

- 6 existing cross-platform Python tests and 5 Windows regression tests passed locally; the same suite runs in GitHub Actions
- End-to-end fixture OCR returned 443 characters consistently
- Forced llama.cpp termination recovered successfully and left zero child processes after exit
- Warm RTX 4060 fixture latency measured about 0.8-0.9 seconds; this is not a general latency guarantee
- 4/8/12/16 GB slot-selection policy is regression-tested; only the 8 GB tier has real-GPU performance evidence

## Important

- The installer is not code-signed. Windows may display an unknown-publisher warning; verify the attached SHA-256 checksum.
- NVIDIA GPU and current driver are required. Only the validated RTX 4060 configuration above is qualified in this preview.
- macOS v0.1.0 remains in the same branch, with a separate SwiftUI/MLX build path. The Windows installer does not install the macOS application.
