#!/usr/bin/env bash
# 构建含 Finder Sync / Quick Look 的双架构 Release 分发包并执行本机冒烟。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${SVNSTUDIO_DERIVED_DATA_PATH:-$ROOT/build/ReleaseDerivedData}"
OUT_DIR="${SVNSTUDIO_RELEASE_OUT_DIR:-$ROOT/dist/release-unsigned}"
RELEASE_ARCHS="arm64 x86_64"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/SVNStudio.app"
APP_PATH="$OUT_DIR/SVNStudio.app"

cd "$ROOT"
echo "==> 构建 Xcode Release（${RELEASE_ARCHS}）"
xcodebuild \
  -project MacSVN.xcodeproj \
  -scheme SVNStudio \
  -configuration Release \
  -destination generic/platform=macOS \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$RELEASE_ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  build

[[ -d "$BUILT_APP" ]] || {
  echo "error: 未找到 Xcode Release 产物: $BUILT_APP" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"

echo "==> 校验 Release 分发包"
"$ROOT/scripts/verify-release-app.sh" "$APP_PATH"

if [[ "${SVNSTUDIO_SKIP_LAUNCH_SMOKE:-0}" != "1" ]]; then
  echo "==> 隔离环境本机启动冒烟"
  "$ROOT/scripts/smoke-test-macos-app.sh" "$APP_PATH"
fi

echo "build-release-app: OK ($APP_PATH)"
