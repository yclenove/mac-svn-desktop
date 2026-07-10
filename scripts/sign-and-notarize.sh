#!/usr/bin/env bash
# Developer ID 签名 + 公证 + staple 骨架（V4 / NFR-10）。
# 默认读取环境变量；SVNSTUDIO_DRY_RUN=1（或兼容 MACSVN_DRY_RUN=1）时只打印将执行的命令。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN="${SVNSTUDIO_DRY_RUN:-${MACSVN_DRY_RUN:-0}}"
APP_PATH="${SVNSTUDIO_APP_PATH:-${MACSVN_APP_PATH:-}}"
IDENTITY="${SVNSTUDIO_SIGN_IDENTITY:-${MACSVN_SIGN_IDENTITY:-}}"
DIST_DIR="${SVNSTUDIO_DIST_DIR:-${MACSVN_DIST_DIR:-$ROOT/dist/release}}"
BUNDLE_ID="${SVNSTUDIO_BUNDLE_ID:-${MACSVN_BUNDLE_ID:-dev.yclenove.svnstudio}}"

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
  SVNSTUDIO_DRY_RUN=1 "$ROOT/scripts/verify-signing-prereqs.sh"
else
  "$ROOT/scripts/verify-signing-prereqs.sh"
fi

if [[ -z "$APP_PATH" ]]; then
  echo "error: 请设置 SVNSTUDIO_APP_PATH 指向待签名的 SVNStudio.app" >&2
  exit 2
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: 请设置 SVNSTUDIO_SIGN_IDENTITY" >&2
  exit 2
fi

mkdir -p "$DIST_DIR"
STAGED_APP="$DIST_DIR/SVNStudio.app"
ZIP_PATH="$DIST_DIR/SVNStudio.zip"

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
if [[ -f "$ROOT/Packaging/SVNStudio/SVNStudio.entitlements" ]]; then
  ENTITLEMENTS_ARGS=(--entitlements "$ROOT/Packaging/SVNStudio/SVNStudio.entitlements")
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
  echo "[dry-run] codesign FinderSync / QuickLook / SVNStudio.app with identity=$IDENTITY"
else
  if [[ -d "$STAGED_APP/Contents/PlugIns/SVNStudioFinderSync.appex" ]]; then
    sign_one "$STAGED_APP/Contents/PlugIns/SVNStudioFinderSync.appex"
  fi
  if [[ -d "$STAGED_APP/Contents/PlugIns/SVNStudioQuickLook.appex" ]]; then
    sign_one "$STAGED_APP/Contents/PlugIns/SVNStudioQuickLook.appex"
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
NOTARY_KEY_ID="${SVNSTUDIO_NOTARY_KEY_ID:-${MACSVN_NOTARY_KEY_ID:-KEY_ID}}"
NOTARY_ISSUER="${SVNSTUDIO_NOTARY_ISSUER_ID:-${MACSVN_NOTARY_ISSUER_ID:-ISSUER_ID}}"
NOTARY_KEY_PATH="${SVNSTUDIO_NOTARY_KEY_PATH:-${MACSVN_NOTARY_KEY_PATH:-/path/to/AuthKey.p8}}"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] xcrun notarytool submit \"$ZIP_PATH\" --key-id $NOTARY_KEY_ID --issuer $NOTARY_ISSUER --key $NOTARY_KEY_PATH --wait"
else
  xcrun notarytool submit "$ZIP_PATH" \
    --key-id "${SVNSTUDIO_NOTARY_KEY_ID:-$MACSVN_NOTARY_KEY_ID}" \
    --issuer "${SVNSTUDIO_NOTARY_ISSUER_ID:-$MACSVN_NOTARY_ISSUER_ID}" \
    --key "${SVNSTUDIO_NOTARY_KEY_PATH:-$MACSVN_NOTARY_KEY_PATH}" \
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
