#!/usr/bin/env bash
# 将 SwiftPM 可执行产物包装为可双击的 MacSVN.app（V1 等价交付路径）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH_TRIPLE="$(swift -print-target-info 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["triple"])' 2>/dev/null || echo "")"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
APP_NAME="MacSVN"
APP_PATH="$OUT_DIR/${APP_NAME}.app"

cd "$ROOT"

echo "==> swift build -c ${CONFIGURATION} --product MacSvnDesktopApp"
swift build -c "$CONFIGURATION" --product MacSvnDesktopApp

BIN=""
if [[ -n "$ARCH_TRIPLE" && -x "$ROOT/.build/${ARCH_TRIPLE}/${CONFIGURATION}/MacSvnDesktopApp" ]]; then
  BIN="$ROOT/.build/${ARCH_TRIPLE}/${CONFIGURATION}/MacSvnDesktopApp"
else
  # 回退：扫描 .build 下匹配配置的产物
  BIN="$(find "$ROOT/.build" -path "*/${CONFIGURATION}/MacSvnDesktopApp" -type f | head -n 1 || true)"
fi

if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  echo "error: 未找到 MacSvnDesktopApp 可执行文件" >&2
  exit 1
fi

echo "==> 使用二进制: $BIN"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Info.plist：将 $(PRODUCT_BUNDLE_IDENTIFIER) 展开为正式 Bundle ID
python3 - <<PY
from pathlib import Path
src = Path("$ROOT/Packaging/MacSVN/Info.plist").read_text(encoding="utf-8")
src = src.replace("\$(PRODUCT_BUNDLE_IDENTIFIER)", "com.yclenove.MacSVN")
Path("$APP_PATH/Contents/Info.plist").write_text(src, encoding="utf-8")
PY

cp "$BIN" "$APP_PATH/Contents/MacOS/MacSVN"
chmod +x "$APP_PATH/Contents/MacOS/MacSVN"
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

# 开发机 ad-hoc 签名，便于本机打开（正式发布走 V4 公证）
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
fi

echo "==> 已生成: $APP_PATH"
exec "$ROOT/scripts/verify-macos-app.sh" "$APP_PATH"
