#!/usr/bin/env bash
# 校验 MacSVN.app 结构与关键 Info.plist 字段（V1 验收）。
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "usage: $0 /path/to/MacSVN.app" >&2
  exit 2
fi

fail() { echo "verify-macos-app: $*" >&2; exit 1; }

[[ -d "$APP_PATH" ]] || fail "不是目录: $APP_PATH"
[[ -f "$APP_PATH/Contents/Info.plist" ]] || fail "缺少 Info.plist"
[[ -x "$APP_PATH/Contents/MacOS/MacSVN" ]] || fail "缺少可执行文件 Contents/MacOS/MacSVN"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "com.yclenove.MacSVN" ]] || fail "CFBundleIdentifier 期望 com.yclenove.MacSVN，实际: ${BUNDLE_ID:-empty}"

EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
[[ "$EXEC" == "MacSVN" ]] || fail "CFBundleExecutable 期望 MacSVN，实际: $EXEC"

SCHEME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[[ "$SCHEME" == "macsvn" ]] || fail "URL scheme 期望 macsvn，实际: ${SCHEME:-empty}"

# Mach-O 可执行
file "$APP_PATH/Contents/MacOS/MacSVN" | grep -q "Mach-O" || fail "MacSVN 不是 Mach-O 可执行文件"

echo "verify-macos-app: OK ($APP_PATH)"
