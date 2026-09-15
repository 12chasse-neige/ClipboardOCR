#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/dist/Clipboard OCR.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/backend"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -framework SwiftUI -framework AppKit -framework Carbon Sources/ClipboardOCR/*.swift -o "$app/Contents/MacOS/ClipboardOCR"
scripts/make-icon.command
cp assets/AppIcon.icns "$app/Contents/Resources/"
cp backend/*.py backend/*.sb "$app/Contents/Resources/backend/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClipboardOCR</string>
<key>CFBundleIdentifier</key><string>local.ClipboardOCR</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Clipboard OCR</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"
