# Clipboard OCR v0.3.0 — macOS and Windows

Second combined release for both native apps. The first combined release, `v0.2.0-preview.4`, remains published unchanged.

## Downloads

| Platform | Asset | Component version |
| --- | --- | --- |
| macOS Apple Silicon | `ClipboardOCR-v0.1.0-macos-arm64.zip` | macOS v0.1.0, reused unchanged from the first combined release |
| Windows x64 / NVIDIA | `ClipboardOCR-0.3.0-windows-x64-setup.exe` | Windows Preview 14 runtime, installer metadata v0.3.0 |

`SHA256SUMS.txt` covers both platform packages. The macOS asset is the previously validated component; the Windows asset is rebuilt from the current `feature/Windows` branch.

## macOS installation

Requires Apple Silicon, macOS 26 or later, and Internet access for initial runtime/model setup. The ZIP contains the app, not the Python environments or model weights.

1. Download and extract `ClipboardOCR-v0.1.0-macos-arm64.zip`, then copy `Clipboard OCR.app` to Applications.
2. For a first installation, install [uv](https://docs.astral.sh/uv/getting-started/installation/) and Apple Command Line Tools (`xcode-select --install`). Download this release's source archive and extract it.
3. Quit Clipboard OCR if it is running. In Terminal, change to the extracted source directory and run `./scripts/setup.command`. This installs the pinned runtimes and downloads the models under `~/Library/Application Support/ClipboardOCR`.
4. Open Clipboard OCR, copy an image, press **Control–Option–Command–O**, and paste the Markdown result.

The macOS app is ad-hoc signed, not notarized; macOS may require opening it through Privacy & Security after checking the download's provenance.

## Windows installation

Requires Windows 10/11 x64, a supported NVIDIA GPU and current driver, about 15 GB free disk space, and Internet access during first setup.

1. Download and run `ClipboardOCR-0.3.0-windows-x64-setup.exe`.
2. Leave **Download the GPU runtime and models now** selected and wait for setup to finish. This is a web installer, not an offline bundle.
3. Launch Clipboard OCR from the desktop shortcut. It starts in the notification area. Copy an image, press **Ctrl–Alt–O**, and paste the Markdown result. Use **Quit** in the tray menu to exit.

The Windows runtime uses the unified cu129 Paddle build for the supported compute capabilities and keeps mutable Python, model and runtime data under `%LOCALAPPDATA%\ClipboardOCR`. The installer is unsigned and may show an unknown-publisher warning; compare the published SHA-256 before running it.

## Validation and reference performance

- macOS: the v0.1.0 component and its validation remain unchanged from the first combined release.
- Windows: the current branch's checks and the real installer test pass; formal hardware validation covers an RTX 4060 Laptop GPU with 8 GB VRAM. A practical reference run observed about 20–30 seconds for the first model load and 2–6 seconds per OCR request afterward. These are single-machine ranges, not a general latency guarantee.
- A separate RTX 5060 user run reported successful setup, about 7.7 seconds for the first model load and about 3 seconds for OCR; this is an additional single-device observation, not full RTX 50-family qualification.
- Both platform packages remain unsigned by a public code-signing identity (macOS uses an ad-hoc signature). Recognition is local after setup; first-run downloads require Internet access.

See [README](https://github.com/12chasse-neige/ClipboardOCR/tree/v0.3.0) and [Windows instructions](https://github.com/12chasse-neige/ClipboardOCR/blob/v0.3.0/WINDOWS.md) for details.
