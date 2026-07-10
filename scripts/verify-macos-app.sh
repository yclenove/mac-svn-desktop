#!/usr/bin/env bash
# 校验 SVNStudio.app 结构与关键 Info.plist 字段。
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "usage: $0 /path/to/SVNStudio.app" >&2
  exit 2
fi

fail() { echo "verify-macos-app: $*" >&2; exit 1; }

[[ -d "$APP_PATH" ]] || fail "不是目录: $APP_PATH"
[[ -f "$APP_PATH/Contents/Info.plist" ]] || fail "缺少 Info.plist"
[[ -x "$APP_PATH/Contents/MacOS/SVNStudio" ]] || fail "缺少可执行文件 Contents/MacOS/SVNStudio"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "dev.yclenove.svnstudio" ]] || fail "CFBundleIdentifier 期望 dev.yclenove.svnstudio，实际: ${BUNDLE_ID:-empty}"

EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
[[ "$EXEC" == "SVNStudio" ]] || fail "CFBundleExecutable 期望 SVNStudio，实际: $EXEC"

SCHEME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[[ "$SCHEME" == "svnstudio" ]] || fail "URL scheme 期望 svnstudio，实际: ${SCHEME:-empty}"

DISPLAY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[[ "$DISPLAY" == "SVN Studio" ]] || fail "CFBundleDisplayName 期望 SVN Studio，实际: ${DISPLAY:-empty}"

file "$APP_PATH/Contents/MacOS/SVNStudio" | grep -q "Mach-O" || fail "SVNStudio 不是 Mach-O 可执行文件"

echo "verify-macos-app: OK ($APP_PATH)"
