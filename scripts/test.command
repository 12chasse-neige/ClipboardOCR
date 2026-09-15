#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python_path="$HOME/Library/Application Support/ClipboardOCR/runtime/bin/python"
"$python_path" -m unittest discover -s tests -v
mkdir -p build
xcrun swiftc -swift-version 5 Sources/ClipboardOCR/Clipboard.swift tests/ClipboardChecks.swift -o build/clipboard-checks
build/clipboard-checks
if [[ "${1:-}" == --integration ]]; then
    if pgrep -x ClipboardOCR > /dev/null; then
        print -u2 "Quit Clipboard OCR before the integration checks."
        exit 1
    fi
    "$python_path" validation/protocol_check.py
    test_app="$PWD/build/ControllerChecks.app"
    mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources/backend"
    cp backend/*.py backend/*.sb "$test_app/Contents/Resources/backend/"
    xcrun swiftc -swift-version 5 -framework SwiftUI -framework AppKit -framework Carbon Sources/ClipboardOCR/Clipboard.swift Sources/ClipboardOCR/Backend.swift Sources/ClipboardOCR/Hotkey.swift Sources/ClipboardOCR/Controller.swift tests/ControllerChecks.swift -o "$test_app/Contents/MacOS/ControllerChecks"
    "$test_app/Contents/MacOS/ControllerChecks" "$PWD/validation/example-1.png"
fi
