#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="VibeNotch Exports/VibeNotch-macOS-Default-1024x1024@1x.png"
ICONSET="icon/AppIcon.iconset"
OUT="icon/AppIcon.icns"

if [ ! -f "$SRC" ]; then
    echo "ERROR: $SRC not found."
    echo "Re-export the Default macOS 1024@1x PNG from Icon Composer (VibeNotch.icon) into 'VibeNotch Exports/'."
    exit 1
fi

echo "==> Rendering iconset from $SRC"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"     >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

echo "==> Compiling $OUT"
iconutil --convert icns "$ICONSET" --output "$OUT"
ls -lh "$OUT"
