#!/usr/bin/env bash
# 将 SwiftPM 可执行产物包装为可双击的 SVNStudio.app。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH_TRIPLE="$(swift -print-target-info 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["triple"])' 2>/dev/null || echo "")"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
APP_NAME="SVNStudio"
APP_PATH="$OUT_DIR/${APP_NAME}.app"
APP_ICON="$ROOT/Packaging/SVNStudio/SVNStudio.icns"

cd "$ROOT"

echo "==> swift build -c ${CONFIGURATION} --product MacSvnDesktopApp"
swift build -c "$CONFIGURATION" --product MacSvnDesktopApp

BIN=""
if [[ -n "$ARCH_TRIPLE" && -x "$ROOT/.build/${ARCH_TRIPLE}/${CONFIGURATION}/MacSvnDesktopApp" ]]; then
  BIN="$ROOT/.build/${ARCH_TRIPLE}/${CONFIGURATION}/MacSvnDesktopApp"
else
  BIN="$(find "$ROOT/.build" -path "*/${CONFIGURATION}/MacSvnDesktopApp" -type f | head -n 1 || true)"
fi

if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  echo "error: 未找到 MacSvnDesktopApp 可执行文件" >&2
  exit 1
fi
if [[ ! -f "$APP_ICON" ]]; then
  echo "error: 缺少应用图标 $APP_ICON" >&2
  exit 1
fi

echo "==> 使用二进制: $BIN"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

python3 - <<PY
from pathlib import Path
src = Path("$ROOT/Packaging/SVNStudio/Info.plist").read_text(encoding="utf-8")
src = src.replace("\$(PRODUCT_BUNDLE_IDENTIFIER)", "dev.yclenove.svnstudio")
Path("$APP_PATH/Contents/Info.plist").write_text(src, encoding="utf-8")
PY

cp "$BIN" "$APP_PATH/Contents/MacOS/SVNStudio"
cp "$APP_ICON" "$APP_PATH/Contents/Resources/SVNStudio.icns"
cp -R "$ROOT/Sources/MacSvnDesktopApp/Resources/en.lproj" "$APP_PATH/Contents/Resources/"
chmod +x "$APP_PATH/Contents/MacOS/SVNStudio"
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
fi

echo "==> 已生成: $APP_PATH"
exec "$ROOT/scripts/verify-macos-app.sh" "$APP_PATH"
