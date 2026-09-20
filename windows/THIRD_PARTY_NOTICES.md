# Third-party components in the Windows installer

The Windows web installer bundles these unmodified command-line runtimes so users do not need to install build tools manually:

- **uv 0.11.19**, copyright Astral Software Inc.; dual-licensed under Apache-2.0 or MIT. The complete license texts are installed under `licenses/`.
- **llama.cpp build b11026** (`b49650adb`), copyright llama.cpp contributors; licensed under MIT. The complete license text is installed under `licenses/`.
- **LLVM OpenMP runtime**, distributed with the llama.cpp Windows package. Its complete license text is installed under `licenses/`.

PaddlePaddle, PaddleOCR, PySide6, Pillow, CUDA runtime packages and model files are downloaded during first-time setup rather than embedded in the installer. Their upstream licenses and notices remain in the installed Python packages and model snapshot.
