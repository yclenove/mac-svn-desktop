#!/usr/bin/env bash
# 校验 SVNStudio.app 已嵌入 Finder Sync .appex。
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "usage: $0 /path/to/SVNStudio.app" >&2
  exit 2
fi

fail() { echo "verify-finder-sync-appex: $*" >&2; exit 1; }

APPEX="$APP_PATH/Contents/PlugIns/SVNStudioFinderSync.appex"
[[ -d "$APPEX" ]] || fail "缺少嵌入扩展: $APPEX"

PLIST="$APPEX/Contents/Info.plist"
[[ -f "$PLIST" ]] || fail "缺少扩展 Info.plist"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "dev.yclenove.svnstudio.FinderSync" ]] || fail "扩展 Bundle ID 期望 dev.yclenove.svnstudio.FinderSync，实际: ${BUNDLE_ID:-empty}"

POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$PLIST" 2>/dev/null || true)"
[[ "$POINT" == "com.apple.FinderSync" ]] || fail "扩展点期望 com.apple.FinderSync，实际: ${POINT:-empty}"

EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
[[ -x "$APPEX/Contents/MacOS/$EXEC_NAME" ]] || fail "缺少扩展可执行文件 Contents/MacOS/$EXEC_NAME"

ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APPEX" 2>/dev/null || true)"
if ! /usr/bin/grep -Eq '<key>com\.apple\.security\.app-sandbox</key>[[:space:]]*<true/>' <<< "$ENTITLEMENTS"; then
  fail "Finder Sync 扩展必须启用 com.apple.security.app-sandbox"
fi
if ! /usr/bin/grep -q '<key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>' <<< "$ENTITLEMENTS"; then
  fail "Finder Sync 扩展缺少 Homebrew SVN 只读执行例外"
fi
for PREFIX in /opt/homebrew/ /usr/local/; do
  /usr/bin/grep -q "<string>$PREFIX</string>" <<< "$ENTITLEMENTS" \
    || fail "Finder Sync 扩展缺少 SVN 执行前缀: $PREFIX"
done
for PREFIX in /Users/ /Volumes/ /private/tmp/; do
  /usr/bin/grep -q "<string>$PREFIX</string>" <<< "$ENTITLEMENTS" \
    || fail "Finder Sync 扩展缺少工作副本只读前缀: $PREFIX"
done

echo "verify-finder-sync-appex: OK ($APPEX)"
