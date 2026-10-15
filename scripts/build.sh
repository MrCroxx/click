#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="build/Click.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Click" "$app/Contents/MacOS/Click"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/icon.swift build/Click.iconset
iconutil -c icns build/Click.iconset -o "$app/Contents/Resources/Click.icns"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
if [[ "${1:-}" == "--zip" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app" "build/Click-macOS-$(uname -m).zip"
fi
