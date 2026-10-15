#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
signing_identity="${SIGNING_IDENTITY:-auto}"
if [[ "$signing_identity" == "auto" ]]; then
    identities=()
    while IFS= read -r identity; do identities+=("$identity"); done < <(
        security find-identity -v -p codesigning | awk '/^[[:space:]]*[0-9]+\)/ { print $2 }'
    )
    if [[ ${#identities[@]} -ne 1 ]]; then
        echo "Set SIGNING_IDENTITY to a Keychain code-signing identity. Found ${#identities[@]} identities; refusing an implicit ad-hoc build." >&2
        exit 1
    fi
    signing_identity="${identities[0]}"
fi
# CI must explicitly opt into ad-hoc signing with SIGNING_IDENTITY=-.
echo "Signing identity: $signing_identity"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="build/Click.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mkdir -p "$app/Contents/Library/LaunchDaemons"
cp Resources/com.mrcroxx.click.daemon.plist Resources/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist "$app/Contents/Library/LaunchDaemons/"
cp "$binary_dir/ClickDaemon" "$app/Contents/MacOS/ClickDaemon"
codesign --force --sign "$signing_identity" "$app/Contents/MacOS/ClickDaemon"
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
codesign --force --sign "$signing_identity" "$app"
codesign --verify --deep --strict "$app"
python3 scripts/verify_service.py "$app"
# Invalidate Finder icon caches when replacing a bundle in place.
touch "$app"
if [[ "${1:-}" == "--zip" ]]; then
    staging="$(mktemp -d "${TMPDIR:-/tmp}/click-stage.XXXXXX")"
    trap 'rm -rf "$staging"' EXIT
    ditto "$app" "$staging/Click.app"
    ln -s /Applications "$staging/Applications"
    python3 scripts/create_macos_dmg.py "$staging" "build/Click-macOS-$(uname -m).dmg" "$app/Contents/Resources/Click.icns" Click
    codesign --force --sign "$signing_identity" "build/Click-macOS-$(uname -m).dmg"
    python3 scripts/verify_dmg.py "build/Click-macOS-$(uname -m).dmg"
    ditto -c -k --sequesterRsrc --keepParent "$app" "build/Click-macOS-$(uname -m).zip"
fi
