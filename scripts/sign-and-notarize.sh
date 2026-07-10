#!/usr/bin/env bash
# Developer ID 签名 + 公证 + staple 骨架（V4 / NFR-10）。
# 默认读取环境变量；MACSVN_DRY_RUN=1 时只打印将执行的命令。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN="${MACSVN_DRY_RUN:-0}"
APP_PATH="${MACSVN_APP_PATH:-}"
IDENTITY="${MACSVN_SIGN_IDENTITY:-}"
DIST_DIR="${MACSVN_DIST_DIR:-$ROOT/dist/release}"
BUNDLE_ID="${MACSVN_BUNDLE_ID:-com.yclenove.MacSVN}"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    "$@"
  fi
}

echo "==> 前置检查"
if [[ "$DRY_RUN" == "1" ]]; then
  MACSVN_DRY_RUN=1 "$ROOT/scripts/verify-signing-prereqs.sh"
else
  "$ROOT/scripts/verify-signing-prereqs.sh"
fi

if [[ -z "$APP_PATH" ]]; then
  echo "error: 请设置 MACSVN_APP_PATH 指向待签名的 MacSVN.app" >&2
  exit 2
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: 请设置 MACSVN_SIGN_IDENTITY" >&2
  exit 2
fi

mkdir -p "$DIST_DIR"
STAGED_APP="$DIST_DIR/MacSVN.app"
ZIP_PATH="$DIST_DIR/MacSVN.zip"

echo "==> 同步应用到 $STAGED_APP"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ditto \"$APP_PATH\" \"$STAGED_APP\""
else
  rm -rf "$STAGED_APP"
  ditto "$APP_PATH" "$STAGED_APP"
fi

echo "==> codesign（Hardened Runtime，deep）"
# 先签扩展，再签主包；--deep 作为兜底
ENTITLEMENTS_ARGS=()
if [[ -f "$ROOT/Packaging/MacSVN/MacSVN.entitlements" ]]; then
  ENTITLEMENTS_ARGS=(--entitlements "$ROOT/Packaging/MacSVN/MacSVN.entitlements")
fi

sign_one() {
  local target="$1"
  run codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$IDENTITY" \
    "${ENTITLEMENTS_ARGS[@]}" \
    "$target"
}

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] codesign FinderSync / QuickLook / MacSVN.app with identity=$IDENTITY"
else
  if [[ -d "$STAGED_APP/Contents/PlugIns/MacSVNFinderSync.appex" ]]; then
    sign_one "$STAGED_APP/Contents/PlugIns/MacSVNFinderSync.appex"
  fi
  if [[ -d "$STAGED_APP/Contents/PlugIns/MacSVNQuickLook.appex" ]]; then
    sign_one "$STAGED_APP/Contents/PlugIns/MacSVNQuickLook.appex"
  fi
  sign_one "$STAGED_APP"
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
fi

echo "==> 打包 zip 供 notarytool"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ditto -c -k --keepParent \"$STAGED_APP\" \"$ZIP_PATH\""
else
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$STAGED_APP" "$ZIP_PATH"
fi

echo "==> notarytool submit"
NOTARY_ARGS=(
  xcrun notarytool submit "$ZIP_PATH"
  --key-id "${MACSVN_NOTARY_KEY_ID:-KEY_ID}"
  --issuer "${MACSVN_NOTARY_ISSUER_ID:-ISSUER_ID}"
  --key "${MACSVN_NOTARY_KEY_PATH:-/path/to/AuthKey.p8}"
  --wait
)

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ${NOTARY_ARGS[*]}"
else
  xcrun notarytool submit "$ZIP_PATH" \
    --key-id "$MACSVN_NOTARY_KEY_ID" \
    --issuer "$MACSVN_NOTARY_ISSUER_ID" \
    --key "$MACSVN_NOTARY_KEY_PATH" \
    --wait
fi

echo "==> stapler staple"
run xcrun stapler staple "$STAGED_APP"
run xcrun stapler validate "$STAGED_APP"

echo "==> Gatekeeper 评估（本机）"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] spctl --assess --type execute --verbose=4 \"$STAGED_APP\""
else
  spctl --assess --type execute --verbose=4 "$STAGED_APP"
fi

echo "==> 完成"
echo "产物: $STAGED_APP"
echo "归档: $ZIP_PATH"
echo "请按 docs/acceptance/H1-manual-checklist.md「干净机冒烟」在未装 Xcode 的机器上验证。"
echo "bundle id 参考: $BUNDLE_ID"
