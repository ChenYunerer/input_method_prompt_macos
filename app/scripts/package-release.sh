#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
OUTPUT_DIR="$WORKSPACE_DIR/dist/releases"
ARCH="$(uname -m)"
case "$ARCH" in arm64) ;; *) printf '仅支持 Apple Silicon（arm64）打包，当前架构：%s\n' "$ARCH" >&2; exit 1 ;; esac
COMMIT="$(git -C "$WORKSPACE_DIR" rev-parse HEAD)"
BUILD_ID="${CI_BUILD_ID:-local}"
if [[ ! "$BUILD_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    printf '无效的构建标识\n' >&2
    exit 1
fi
mkdir -p "$PROJECT_DIR/.build" "$OUTPUT_DIR"
PACKAGE_TMP="$(mktemp -d "$PROJECT_DIR/.build/release-package.XXXXXX")"
trap 'rm -rf -- "$PACKAGE_TMP"' EXIT
APP_PATH="$PACKAGE_TMP/中英提示.app"
INPUT_PROMPT_APP_DIR="$APP_PATH" bash "$PROJECT_DIR/scripts/build-app.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ || ! "$APP_BUILD" =~ ^[0-9]+$ ]]; then
    printf '应用包版本信息无效\n' >&2
    exit 1
fi
PREFIX="InputMethodPrompt-v${VERSION}-build${APP_BUILD}-ci${BUILD_ID}-${COMMIT:0:12}-${ARCH}"
test "$(lipo -archs "$APP_PATH/Contents/MacOS/InputMethodPrompt")" = "$ARCH"
codesign --verify --strict "$APP_PATH"
# Archive the bundle before artifact upload to preserve its structure and executable bit.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$PACKAGE_TMP/$PREFIX.zip"
ditto -x -k "$PACKAGE_TMP/$PREFIX.zip" "$PACKAGE_TMP/unpacked"
test -x "$PACKAGE_TMP/unpacked/中英提示.app/Contents/MacOS/InputMethodPrompt"
codesign --verify --strict "$PACKAGE_TMP/unpacked/中英提示.app"
mv "$PACKAGE_TMP/$PREFIX.zip" "$OUTPUT_DIR/"
python3 - "$OUTPUT_DIR/$PREFIX.json" "$VERSION" "$APP_BUILD" "$BUILD_ID" "$COMMIT" "$ARCH" <<'PY'
import json
import sys
from pathlib import Path
path, version, app_build, ci_build, commit, arch = sys.argv[1:]
Path(path).write_text(json.dumps({
    "version": version, "app_build": app_build, "ci_build": ci_build,
    "commit": commit, "architecture": arch, "minimum_macos": "13.0",
    "signing": "ad-hoc", "notarized": False,
}, indent=2) + "\n")
PY
cd "$OUTPUT_DIR"
shasum -a 256 "$PREFIX.zip" "$PREFIX.json" > "$PREFIX.sha256"
printf '已生成下载包：%s/%s.zip\n' "$OUTPUT_DIR" "$PREFIX"
