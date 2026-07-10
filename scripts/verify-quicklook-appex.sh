#!/usr/bin/env bash
# 校验 SVNStudio.app 已嵌入 Quick Look .appex。
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "usage: $0 /path/to/SVNStudio.app" >&2
  exit 2
fi

fail() { echo "verify-quicklook-appex: $*" >&2; exit 1; }

APPEX="$APP_PATH/Contents/PlugIns/SVNStudioQuickLook.appex"
[[ -d "$APPEX" ]] || fail "缺少嵌入扩展: $APPEX"

PLIST="$APPEX/Contents/Info.plist"
[[ -f "$PLIST" ]] || fail "缺少扩展 Info.plist"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "dev.yclenove.svnstudio.QuickLook" ]] || fail "扩展 Bundle ID 期望 dev.yclenove.svnstudio.QuickLook，实际: ${BUNDLE_ID:-empty}"

POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$PLIST" 2>/dev/null || true)"
[[ "$POINT" == "com.apple.quicklook.preview" ]] || fail "扩展点期望 com.apple.quicklook.preview，实际: ${POINT:-empty}"

EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
[[ -x "$APPEX/Contents/MacOS/$EXEC_NAME" ]] || fail "缺少扩展可执行文件 Contents/MacOS/$EXEC_NAME"

echo "verify-quicklook-appex: OK ($APPEX)"
