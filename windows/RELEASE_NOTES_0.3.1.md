# Clipboard OCR v0.3.1 — macOS and Windows

This release keeps the macOS component and fixes the Windows installer so the user can choose where the large runtime and model files are stored.

## Downloads

| Platform | Asset | Component version |
| --- | --- | --- |
| macOS Apple Silicon | `ClipboardOCR-v0.1.0-macos-arm64.zip` | macOS v0.1.0, reused unchanged from v0.3.0 |
| Windows x64 / NVIDIA | `ClipboardOCR-0.3.1-windows-x64-setup.exe` | Windows v0.3.1 |

`SHA256SUMS.txt` contains the SHA-256 checksum of both assets.

## Windows storage and setup

The installer always displays **Select Destination Location**. Choose a writable folder on the drive with room for the runtime. Python, CUDA-enabled Paddle packages, the resumable Paddle wheel download, OCR models, inference caches, and app logs are stored under `<selected install folder>\data`. The setup transcript and small child-process logs remain under `%LOCALAPPDATA%\ClipboardOCR\logs`.

Allow at least **25 GiB free** on the selected drive and an Internet connection for first setup. A validated cold setup occupied about **16.5 GiB** under the selected application folder, so the preflight leaves room for temporary and resumable downloads. Setup verifies Python, the virtual environment, and uv's ability to inspect the selected path before downloading large files. If a Windows mount-point or security policy blocks the location, setup stops before those large downloads; choose another ordinary writable path and rerun.

Runtime and model data from previous versions under `%LOCALAPPDATA%\ClipboardOCR` is not moved or deleted. After the v0.3.1 setup succeeds and GPU OCR has been verified, users may remove old data folders manually if they no longer need them.

## GPU compatibility and validation

Requires Windows 10/11 x64, an NVIDIA GPU with compute capability **7.5, 8.0, 8.6, 8.9 or 12.0**, NVIDIA Windows driver **576.02 or newer**, at least 25 GiB free disk space on the chosen install drive, and Internet access for first setup. The pinned Paddle CUDA 12.9 wheel includes RTX 40-series compute capability 8.9. Unsupported GPU architectures stop before large downloads.

The release installer is unsigned. Verify its SHA-256 against `SHA256SUMS.txt` before launching it. No administrator rights are required for a per-user installation.

Formal end-to-end GPU OCR validation is on one Windows 11 / RTX 4060 Laptop 8 GB machine; it does not constitute individual hardware validation for every RTX 40-series model. One observed RTX 4060 run took about **20–30 seconds for first model load** and **2–6 seconds per OCR request afterward**. These are single-machine observations, not performance guarantees.

## macOS

The macOS v0.1.0 Apple Silicon app is reused unchanged from v0.3.0. It remains ad-hoc signed and not notarized.
