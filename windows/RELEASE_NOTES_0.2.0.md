# Clipboard OCR v0.2.0 Windows Preview 3

Updated downloadable Windows installer built from `feature/Windows`. This is a **web installer**, not a complete offline bundle: it includes pinned setup tools and downloads about 6 GB of GPU runtime and model data during first setup.

## Validated configuration

- Windows 11 Home x64, build 26200
- NVIDIA GeForce RTX 4060 Laptop GPU, 8 GB VRAM
- PaddlePaddle GPU 3.2.1 / CUDA 12.6 / cuDNN 9.9.0.52
- PaddleOCR 3.7.0 / PaddleOCR-VL 1.6
- llama.cpp b11026, two automatically selected Vulkan inference slots

## Included

- High-DPI desktop and tray interface with `Ctrl+Alt+O` global OCR shortcut
- Starts silently in the notification area; closing the window returns it to the tray instead of exiting
- Console-free desktop launch through `pythonw.exe`; backend processes also use no-window creation flags
- Local image-to-Markdown recognition for prose, equations and document layout
- Clipboard change protection and 64-bit multi-megabyte Unicode output
- Bounded preprocessing for inputs above 12 megapixels
- Automatic one-time recovery when the llama.cpp service crashes
- Rotating local diagnostics that do not record images or recognized text
- Idempotent source/runtime setup and revision-pinned GGUF model download
- Conservative VRAM-based selection of one to four inference slots, with an explicit environment override

## Verification

- 6 existing cross-platform Python tests and 6 Windows regression tests passed locally; the same suite runs in GitHub Actions
- End-to-end fixture OCR returned 443 characters consistently
- Forced llama.cpp termination recovered successfully and left zero child processes after exit
- Warm RTX 4060 fixture latency measured about 0.8-0.9 seconds; this is not a general latency guarantee
- 4/8/12/16 GB slot-selection policy is regression-tested; only the 8 GB tier has real-GPU performance evidence

## Important

- The installer is not code-signed. Windows may display an unknown-publisher warning; verify the attached SHA-256 checksum.
- NVIDIA GPU and current driver are required. Only the validated RTX 4060 configuration above is qualified in this preview.
- macOS v0.1.0 remains in the same branch, with a separate SwiftUI/MLX build path. The Windows installer does not install the macOS application.
