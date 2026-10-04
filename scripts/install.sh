#!/bin/bash
# Builds Pulse, replaces the copy in /Applications (or ~/Applications) and starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh "$@"

TARGET_DIR="/Applications"
[[ -w "$TARGET_DIR" ]] || TARGET_DIR="$HOME/Applications"
mkdir -p "$TARGET_DIR"

# Quit a running copy (it would keep the old binary alive).
osascript -e 'tell application id "space.zenkovich.pulse" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do pgrep -xq Pulse || break; sleep 0.2; done
pkill -x Pulse 2>/dev/null || true

rm -rf "$TARGET_DIR/Pulse.app"
cp -R build/Pulse.app "$TARGET_DIR/Pulse.app"
open "$TARGET_DIR/Pulse.app"
echo "Installed to $TARGET_DIR/Pulse.app and started"
