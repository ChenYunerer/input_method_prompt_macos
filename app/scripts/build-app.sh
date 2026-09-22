#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
# Relative overrides are resolved from the caller's working directory.
APP_DIR="${INPUT_PROMPT_APP_DIR:-$WORKSPACE_DIR/dist/中英提示.app}"
case "$APP_DIR" in
    /*) ;;
    *) APP_DIR="$PWD/$APP_DIR" ;;
esac
APP_NAME="$(basename "$APP_DIR")"
case "$APP_NAME" in
    *.app) ;;
    *) printf '输出路径必须以 .app 结尾：%s\n' "$APP_DIR" >&2; exit 1 ;;
esac
APP_PARENT="$(dirname "$APP_DIR")"
mkdir -p "$APP_PARENT"
APP_PARENT="$(cd "$APP_PARENT" && pwd -P)"
APP_DIR="$APP_PARENT/$APP_NAME"
LOCK_DIR="$APP_PARENT/.$APP_NAME.build-lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '无法取得构建锁，请确认没有其他构建正在写入该输出：%s\n' "$LOCK_DIR" >&2
    exit 1
fi

STAGING_ROOT=""
BACKUP_APP=""
INSTALLED=0
cleanup() {
    local result=$?
    local preserve_staging=0
    trap - EXIT HUP INT TERM
    if [[ -n "$BACKUP_APP" && -d "$BACKUP_APP" && "$INSTALLED" -eq 0 ]]; then
        if [[ ! -e "$APP_DIR" && ! -L "$APP_DIR" ]] && mv "$BACKUP_APP" "$APP_DIR"; then
            printf '构建安装未完成，已恢复原应用：%s\n' "$APP_DIR" >&2
        else
            # Never overwrite a path created by another process during rollback.
            preserve_staging=1
            printf '无法安全恢复原应用，备份已保留：%s\n' "$BACKUP_APP" >&2
            result=1
        fi
    fi
    if [[ -n "$STAGING_ROOT" && "$preserve_staging" -eq 0 ]]; then
        rm -rf -- "$STAGING_ROOT" || result=1
    fi
    rmdir "$LOCK_DIR" || result=1
    exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -L "$APP_DIR" || ( -e "$APP_DIR" && ! -d "$APP_DIR" ) ]]; then
    printf '输出路径必须是普通应用目录，不能是符号链接或文件：%s\n' "$APP_DIR" >&2
    exit 1
fi
STAGING_ROOT="$(mktemp -d "$APP_PARENT/.$APP_NAME.build.XXXXXX")"
STAGED_APP="$STAGING_ROOT/package/$APP_NAME"
BACKUP_APP="$STAGING_ROOT/previous.app"

cd "$PROJECT_DIR"
bash scripts/build-icon.sh
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/InputMethodPrompt" "$STAGED_APP/Contents/MacOS/InputMethodPrompt"
cp "$PROJECT_DIR/.build/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
cat > "$STAGED_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>InputMethodPrompt</string>
    <key>CFBundleIdentifier</key><string>local.yun.InputMethodPrompt</string>
    <key>CFBundleName</key><string>中英提示</string>
    <key>CFBundleDisplayName</key><string>中英提示</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundleShortVersionString</key><string>1.11.1</string>
    <key>CFBundleVersion</key><string>30</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
touch "$STAGED_APP"

# All paths live on the output filesystem. Preserve the old bundle until the
# verified new bundle has been moved into place; EXIT restores it on failure.
if [[ -e "$APP_DIR" || -L "$APP_DIR" ]]; then
    if [[ -L "$APP_DIR" || ! -d "$APP_DIR" ]]; then
        printf '输出路径在构建期间发生变化，已停止替换：%s\n' "$APP_DIR" >&2
        exit 1
    fi
    mv "$APP_DIR" "$BACKUP_APP"
fi
if [[ -e "$APP_DIR" || -L "$APP_DIR" ]]; then
    printf '输出路径已被其他进程占用，已停止替换：%s\n' "$APP_DIR" >&2
    exit 1
fi
mv "$STAGED_APP" "$APP_DIR"
INSTALLED=1
printf '\n已生成：%s\n' "$APP_DIR"
