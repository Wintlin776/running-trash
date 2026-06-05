#!/bin/bash
# Builds RunningTrash.app from the Swift sources using the Command Line Tools
# (no full Xcode required). Run from the project root: ./build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/RunningTrash.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "==> Cleaning previous build"
rm -rf "$ROOT/build"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Compiling Swift sources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc \
    -sdk "$SDK" \
    -target arm64-apple-macos13.0 \
    -parse-as-library \
    -O \
    -framework AppKit \
    -o "$MACOS_DIR/RunningTrash" \
    "$ROOT"/Sources/*.swift

echo "==> Assembling app bundle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "==> AppIcon.icns missing — generating it"
    "$ROOT/make_icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Launch with: open \"$APP\""
