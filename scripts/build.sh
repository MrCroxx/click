#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="build/Click.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mkdir -p "$app/Contents/Library/LaunchDaemons"
cp Resources/com.mrcroxx.click.daemon.plist Resources/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist "$app/Contents/Library/LaunchDaemons/"
cp "$binary_dir/ClickDaemon" "$app/Contents/MacOS/ClickDaemon"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app/Contents/MacOS/ClickDaemon"
cp "$binary_dir/Click" "$app/Contents/MacOS/Click"
cp Resources/Info.plist "$app/Contents/Info.plist"
for bundle in "$binary_dir"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
mkdir -p "$app/Contents/Resources/ThirdParty"
cp -R Sources/VirtualHID/Licenses "$app/Contents/Resources/ThirdParty/"
cp Sources/VirtualHID/UPSTREAM.md "$app/Contents/Resources/ThirdParty/"
swift scripts/icon.swift build/Click.iconset
iconutil -c icns build/Click.iconset -o "$app/Contents/Resources/Click.icns"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
if [[ "${1:-}" == "--zip" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app" "build/Click-macOS-$(uname -m).zip"
fi
