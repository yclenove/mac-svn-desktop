#!/usr/bin/env bash
# 校验可分发 SVNStudio.app 的扩展、架构、签名与动态依赖。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-}"
REQUIRED_ARCHS="arm64 x86_64"

if [[ -z "$APP_PATH" ]]; then
  echo "usage: $0 /path/to/SVNStudio.app" >&2
  exit 2
fi

fail() { echo "verify-release-app: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"
}

bundle_executable() {
  local bundle="$1"
  local executable
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist" 2>/dev/null || true)"
  [[ -n "$executable" ]] || fail "无法读取 CFBundleExecutable: $bundle"
  printf '%s/Contents/MacOS/%s\n' "$bundle" "$executable"
}

need_cmd codesign

"$ROOT/scripts/verify-macos-app.sh" "$APP_PATH"
"$ROOT/scripts/verify-finder-sync-appex.sh" "$APP_PATH"
"$ROOT/scripts/verify-quicklook-appex.sh" "$APP_PATH"

FINDER_APPEX="$APP_PATH/Contents/PlugIns/SVNStudioFinderSync.appex"
QUICKLOOK_APPEX="$APP_PATH/Contents/PlugIns/SVNStudioQuickLook.appex"
MAIN_EXECUTABLE="$(bundle_executable "$APP_PATH")"
FINDER_EXECUTABLE="$(bundle_executable "$FINDER_APPEX")"
QUICKLOOK_EXECUTABLE="$(bundle_executable "$QUICKLOOK_APPEX")"

"$ROOT/scripts/verify-mach-o-dependencies.sh" "$APP_PATH" "$MAIN_EXECUTABLE" "$(dirname "$MAIN_EXECUTABLE")" "主应用"
"$ROOT/scripts/verify-mach-o-dependencies.sh" "$APP_PATH" "$FINDER_EXECUTABLE" "$(dirname "$FINDER_EXECUTABLE")" "Finder Sync"
"$ROOT/scripts/verify-mach-o-dependencies.sh" "$APP_PATH" "$QUICKLOOK_EXECUTABLE" "$(dirname "$QUICKLOOK_EXECUTABLE")" "Quick Look"

if /usr/bin/plutil -p "$APP_PATH/Contents/Info.plist" | /usr/bin/grep -q '\$('; then
  fail "主应用 Info.plist 仍含未展开的构建变量"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "verify-release-app: OK ($APP_PATH; archs=$REQUIRED_ARCHS)"
