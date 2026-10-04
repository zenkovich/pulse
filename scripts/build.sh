#!/bin/bash
# Builds Pulse.app into build/. Usage: scripts/build.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/Pulse.app"

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

if [[ ! -f build/Pulse.icns || scripts/make-icon.swift -nt build/Pulse.icns ]]; then
    rm -rf build/Pulse.iconset
    mkdir -p build
    swift scripts/make-icon.swift build/Pulse.iconset
    iconutil -c icns build/Pulse.iconset -o build/Pulse.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pulse" "$APP/Contents/MacOS/Pulse"
cp build/Pulse.icns "$APP/Contents/Resources/Pulse.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for a locally built app and for SMAppService to identify it.
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
