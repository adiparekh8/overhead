#!/bin/bash
# Builds build/Overhead.app with the Swift command line tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Overhead"

APP="build/Overhead.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Overhead"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Sign for this Mac only. Location Services needs a signed app bundle.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with:  open \"$(pwd)/$APP\""
