#!/bin/bash
# Manually sign the existing app bundle; this script never builds or changes keychain settings.
set -euo pipefail
cd "$(dirname "$0")/.."
app=SimpleClipboardHistory.app
identity=${SIGNING_IDENTITY:-evadnoob Local Code Signing}
if [[ ! -d "$app" ]]; then
    echo "Missing $app; run bash bundle.sh first." >&2
    exit 1
fi
codesign --force -s "$identity" "$app"
codesign --verify --strict "$app"
echo "Signed $app with \"$identity\""
