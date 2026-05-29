#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT_DIR/DSkiller.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$SCRIPT_DIR/Assets/DSkillerIcon.iconset"
ICON_PNG="$SCRIPT_DIR/Assets/DSkillerIcon-1024.png"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

"$SCRIPT_DIR/scripts/generate_icon.py" >/dev/null
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$RESOURCES/DSkillerIcon.icns"

swiftc \
  "$SCRIPT_DIR/Sources/"*.swift \
  -framework AppKit \
  -o "$MACOS/DSkiller"

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS/DSkiller"

echo "$APP"
