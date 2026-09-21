#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="$PROJECT_DIR/Assets/AppIcon.png"
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Standard and Retina representations for Finder, the Dock, and system settings.
for variant in \
    '16:icon_16x16.png' '32:icon_16x16@2x.png' \
    '32:icon_32x32.png' '64:icon_32x32@2x.png' \
    '128:icon_128x128.png' '256:icon_128x128@2x.png' \
    '256:icon_256x256.png' '512:icon_256x256@2x.png' \
    '512:icon_512x512.png' '1024:icon_512x512@2x.png'; do
    size="${variant%%:*}"
    filename="${variant#*:}"
    sips -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/$filename" >/dev/null
done
iconutil --convert icns "$ICONSET_DIR" --output "$PROJECT_DIR/.build/AppIcon.icns"
printf '已生成应用图标：%s\n' "$PROJECT_DIR/.build/AppIcon.icns"
