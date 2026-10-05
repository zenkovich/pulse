#!/bin/bash
# Builds a universal (arm64 + x86_64) Pulse.app and packs it into dist/Pulse-<version>.zip.
# Usage: scripts/package.sh [--native]   (--native: this Mac's architecture only, faster)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--native" ]]; then
    scripts/build.sh
else
    scripts/build.sh --universal
fi

APP="build/Pulse.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHIVE="dist/Pulse-$VERSION.zip"

codesign --verify --strict "$APP"
mkdir -p dist
rm -f "$ARCHIVE"
# ditto keeps the bundle's symlinks, extended attributes and signature intact (plain zip can break them).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo "Archive: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/Pulse"))"
echo "SHA-256: $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
