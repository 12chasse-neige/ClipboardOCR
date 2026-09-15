#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/build.command
ditto -c -k --sequesterRsrc --keepParent "dist/Clipboard OCR.app" "dist/ClipboardOCR-v0.1.0-macos-arm64.zip"
print "Packaged: $PWD/dist/ClipboardOCR-v0.1.0-macos-arm64.zip"
