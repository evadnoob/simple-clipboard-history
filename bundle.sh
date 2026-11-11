#!/bin/bash
# Build and package an ad-hoc signed development app without accessing the keychain.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product SimpleClipboardHistory
app=SimpleClipboardHistory.app
icon=Resources/AppIcon.icns
if [[ ! -f "$icon" ]]; then
    echo "Missing $icon; generate it with swift tools/generate-app-icon.swift." >&2
    exit 1
fi
stage=$(mktemp -d "./.SimpleClipboardHistory.build.XXXXXX")
backup="${app}.previous.$$"
restore=0
cleanup() {
    status=$?
    if (( restore )); then
        rm -rf "$app"
        if [[ -e "$backup" ]]; then mv "$backup" "$app"; fi
    fi
    rm -rf "$stage"
    exit "$status"
}
trap cleanup EXIT
mkdir -p "$stage/$app/Contents/MacOS" "$stage/$app/Contents/Resources"
cp .build/release/SimpleClipboardHistory "$stage/$app/Contents/MacOS/SimpleClipboardHistory"
cp "$icon" "$stage/$app/Contents/Resources/AppIcon.icns"
cat > "$stage/$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SimpleClipboardHistory</string>
<key>CFBundleIdentifier</key><string>com.evadnoob.simple-clipboard-history</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Simple Clipboard History</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$stage/$app"
codesign --verify --strict "$stage/$app"
if [[ -e "$app" ]]; then mv "$app" "$backup"; restore=1; fi
mv "$stage/$app" "$app"
if (( restore )); then rm -rf "$backup"; restore=0; fi
echo "Built ad-hoc signed $app"
