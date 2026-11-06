#!/bin/bash
# Build a release binary and wrap it in SimpleClipboard.app (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"
# Only the app: the test harness products use @testable import and do not build in release.
swift build -c release --product SimpleClipboard
app=SimpleClipboard.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/SimpleClipboard "$app/Contents/MacOS/SimpleClipboard"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SimpleClipboard</string>
<key>CFBundleIdentifier</key><string>com.evadnoob.simple-clipboard</string>
<key>CFBundleName</key><string>Simple Clipboard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$app"
echo "Built $app"
