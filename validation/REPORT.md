# v0.1.0 validation record

Date: 2026-09-16. Hardware: Apple M4 Pro, 48 GB unified memory. OS: macOS 26.6.2 (25G83). Native build: Apple Swift 6.3.3, arm64. Python 3.12.13; exact dependency versions/hashes are in the two backend lock files.

## Backend-first gate

The documented full PaddleOCR-VL-1.6 pipeline with `mlx-vlm-server` ran successfully before the interface was built. PP-DocLayoutV3 uses PaddlePaddle on the CPU; PaddleOCR-VL-1.6 uses MLX/Metal on the GPU. No alternate OCR model was substituted.

The first combined-environment trial revealed overlapping OpenCV packages. The final version uses two isolated environments. Both pass `uv pip check`, and setup restores them with `--require-hashes`.

Model files initially in Caches disappeared between sessions. The final installation stores fixed model snapshots in Application Support. Both fixtures and integration tests were rerun after restoring the models there.

## Transcription review

Inputs: `example-1.png` (English), `example-2.png` (Chinese), and a TIFF encoding of the English page. Both PNG pages are 1500 × 1417 pixels. Their LaTeX source is `examples.tex`.

| Content | Observation |
|---|---|
| English / Chinese prose | Reading order and main sentences preserved. |
| Numbered statements | `1.` and `2.` preserved on each page. |
| Greek letters and subscripts | `x_i`, `alpha_i`, `beta_i^2`, `a_ij` retained. |
| Display equations | Energy equation and matrix/vector product remain separate display blocks. |
| Fractions | `1/2` and `(a+b)/(c+d)` correctly represented with LaTeX fractions. |
| Matrices | Both 2×2 matrix rows and both vector entries preserved. |
| Equation numbers | `(1)`–`(4)` preserved after explicitly enabling formula-number export. |
| Lists | Typographic bullets become Markdown list markers. |
| Known symbol error | Source `\hbar` becomes `\overline{h}` in English and `\bar{h}` in Chinese. No automatic correction. |
| Formatting differences | The inline range `i=1,2,3` becomes plain text; the final Chinese full stop is absent in output. |

The exact output files are `example-1.actual.md` and `example-2.actual.md`. The README embeds those outputs beside the inputs. This is manual inspection of two synthetic pages, not a comprehensive OCR benchmark or a claim of perfect mathematical transcription.

## Performance

See `measurements.json` for the final offline run. The fresh-process total includes service startup, layout initialization, and first-page inference. Warm requests reuse the same worker/service. Measurements exclude initial setup/downloads and do not flush the OS file cache.

Memory is the peak sampled sum of RSS for the benchmark process and its descendants (100 ms sampling). It is not a separate Metal allocation measurement and can double-count shared pages. Input size, layout, and expression length affect timings.

## Automated checks

`./scripts/test.command --integration` passed:

- Six Python tests: missing-model rejection, stopped-service handling, math delimiter conversion, LaTeX interior/matrix/tag preservation, escaped dollar handling, and list normalization outside math.
- AppKit tests on a unique pasteboard: empty, plain text, PNG, TIFF, conditional automatic copy, and changed-clipboard preservation.
- Actual worker PNG and TIFF inference, warm model reuse (same child PID), forced MLX-service crash, recovery, and input deletion after both success and failure.
- Worker EOF shutdown leaves no surviving owned MLX child.
- Worker diagnostics contain only allowlisted codes (`recognition_complete`, `backend_crashed`); no fixture content appears in diagnostics.
- Native controller integration with the packaged backend resources: empty-clipboard error, success-to-clipboard loop, ignored duplicate trigger, newer-clipboard preservation, explicit Copy OCR Result, and model unload.

The native controller tests use a unique pasteboard and therefore do not modify the user's general clipboard. The deliberate general-clipboard fixture helper used during UI checks holds the original contents in memory and restores them only if the clipboard still contains test data.

## Offline and packaging checks

- The final benchmark runs under `sandbox-exec -f backend/local-only.sb`. External outbound networking is denied; localhost traffic is allowed.
- A separate external HTTPS attempt under that profile fails, while OCR completes successfully through localhost.
- Explicit local model paths and HF/Transformers offline flags are enabled. MLX vision caching and prefix/disk caching are disabled.
- Swift app builds successfully with an arm64 macOS 26 deployment target.
- The `.app` passes `codesign --verify --deep --strict`.
- The Info.plist names the generated AppIcon and enables menu-bar-only (`LSUIElement`) behavior.
- The generated master is an RGBA PNG with transparent pixels; the ICNS contains the standard 16–1024 pixel representations.
- Settings were opened and visually inspected. Text wraps without truncation, the app icon appears, and custom shortcut recording plus restoring the default were exercised.

## Physical keyboard check

Passed: the user pressed Control–Option–Command–O on the physical keyboard and confirmed “Markdown copied.” The fixture helper independently verified that the general clipboard contained the expected English Markdown, equation number, and matrix (`markdown=true`, `numbered=true`, `matrix=true`, `image=false`). The previous clipboard contents were restored afterward.

App-targeted automation key events did not activate Carbon's system hotkey, so physical-key confirmation was used rather than misrepresenting those synthetic events as a successful global-key test. Custom shortcut recording and restoring the default were also exercised in Settings.

## Remaining scope

Broader natural-document accuracy, other Apple Silicon machines, older macOS releases, public distribution/notarization, and a multi-day memory-leak soak are outside this first-version validation.
