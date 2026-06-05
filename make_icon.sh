#!/bin/bash
# Generates Resources/AppIcon.icns from the custom TrashIcon drawing.
# Run before build.sh whenever the icon art changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Building icon generator"
xcrun swiftc \
    -sdk "$SDK" \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -o "$TMP/genicon" \
    "$ROOT/Sources/TrashIcon.swift" "$ROOT/Tools/main.swift"

echo "==> Rendering iconset"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
"$TMP/genicon" "$ICONSET"

echo "==> Packing AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

echo "==> Done: $ROOT/Resources/AppIcon.icns"
