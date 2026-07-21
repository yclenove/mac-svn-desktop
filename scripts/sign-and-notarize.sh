#!/usr/bin/env bash
# Developer ID 签名 + 公证 + staple 分发流程（V4 / NFR-10）。
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
case "$IDENTITY" in
  "Developer ID Application:"*) ;;
  *)
    echo "error: 签名身份必须是 Developer ID Application: $IDENTITY" >&2
    exit 2
    ;;
esac

mkdir -p "$DIST_DIR"
STAGING_DIR="$DIST_DIR/.svnstudio-signing"
STAGED_APP="$STAGING_DIR/SVNStudio.app"
FINAL_APP="$DIST_DIR/SVNStudio.app"
SUBMISSION_ZIP="$DIST_DIR/SVNStudio-notary-submission.zip"
FINAL_ZIP="$DIST_DIR/SVNStudio.zip"
FINAL_ZIP_TEMP="$DIST_DIR/.SVNStudio.zip.tmp"
NOTARY_RESULT="$DIST_DIR/notary-result.json"

cleanup() {
  if [[ "$DRY_RUN" != "1" ]]; then
    rm -f "$FINAL_ZIP_TEMP"
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

INPUT_APP_CANONICAL=""
FINAL_APP_CANONICAL="$(cd -P "$DIST_DIR" && pwd)/SVNStudio.app"
if [[ -d "$APP_PATH" ]]; then
  INPUT_APP_CANONICAL="$(cd -P "$APP_PATH" && pwd)"
fi
if [[ -d "$FINAL_APP" ]]; then
  FINAL_APP_CANONICAL="$(cd -P "$FINAL_APP" && pwd)"
fi
if [[ -n "$INPUT_APP_CANONICAL" && "$INPUT_APP_CANONICAL" == "$FINAL_APP_CANONICAL" ]]; then
  echo "error: 输入应用不能与最终发布路径相同: $FINAL_APP" >&2
  exit 2
fi

echo "==> 校验输入 Release 应用"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] $ROOT/scripts/verify-release-app.sh \"$APP_PATH\""
else
  "$ROOT/scripts/verify-release-app.sh" "$APP_PATH"
fi

echo "==> 准备发布工作目录"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] rm -rf \"$FINAL_APP\" \"$STAGING_DIR\""
  echo "[dry-run] rm -f \"$FINAL_ZIP\" \"$FINAL_ZIP_TEMP\""
  echo "[dry-run] mkdir -p \"$STAGING_DIR\""
else
  rm -rf "$FINAL_APP" "$STAGING_DIR"
  rm -f "$FINAL_ZIP" "$FINAL_ZIP_TEMP"
  mkdir -p "$STAGING_DIR"
fi

echo "==> 同步应用到 $STAGED_APP"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ditto \"$APP_PATH\" \"$STAGED_APP\""
else
  rm -rf "$STAGED_APP"
  ditto "$APP_PATH" "$STAGED_APP"
fi

echo "==> codesign（Hardened Runtime；先扩展后主包）"
FINDER_ENTITLEMENTS="$ROOT/Packaging/FinderSync/SVNStudioFinderSync.entitlements"
MAIN_ENTITLEMENTS="$ROOT/Packaging/SVNStudio/SVNStudio.entitlements"

sign_one() {
  local target="$1"
  local entitlements="${2:-}"
  local arguments=(
    --force
    --options runtime
    --timestamp
    --sign "$IDENTITY"
  )
  if [[ -n "$entitlements" ]]; then
    arguments+=(--entitlements "$entitlements")
  fi
  run codesign "${arguments[@]}" "$target"
}

developer_id_team() {
  local target="$1"
  local details
  local team
  details="$(codesign -dv --verbose=4 "$target" 2>&1)" \
    || { echo "error: 无法读取签名详情: $target" >&2; return 1; }
  /usr/bin/grep -Fq 'Authority=Developer ID Application:' <<< "$details" \
    || { echo "error: 不是 Developer ID Application 签名: $target" >&2; return 1; }
  team="$(/usr/bin/awk -F= '$1 == "TeamIdentifier" { print $2; exit }' <<< "$details")"
  [[ -n "$team" && "$team" != "not set" ]] \
    || { echo "error: 签名缺少 TeamIdentifier: $target" >&2; return 1; }
  printf '%s\n' "$team"
}

sign_one "$STAGED_APP/Contents/PlugIns/SVNStudioFinderSync.appex" "$FINDER_ENTITLEMENTS"
sign_one "$STAGED_APP/Contents/PlugIns/SVNStudioQuickLook.appex"
if [[ -f "$MAIN_ENTITLEMENTS" ]]; then
  sign_one "$STAGED_APP" "$MAIN_ENTITLEMENTS"
else
  sign_one "$STAGED_APP"
fi

if [[ "$DRY_RUN" != "1" ]]; then
  FINDER_TEAM="$(developer_id_team "$STAGED_APP/Contents/PlugIns/SVNStudioFinderSync.appex")"
  QUICKLOOK_TEAM="$(developer_id_team "$STAGED_APP/Contents/PlugIns/SVNStudioQuickLook.appex")"
  MAIN_TEAM="$(developer_id_team "$STAGED_APP")"
  [[ "$MAIN_TEAM" == "$FINDER_TEAM" && "$MAIN_TEAM" == "$QUICKLOOK_TEAM" ]] || {
    echo "error: 主应用与扩展 TeamIdentifier 不一致" >&2
    exit 1
  }
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
  "$ROOT/scripts/verify-release-app.sh" "$STAGED_APP"
fi

echo "==> 打包 zip 供 notarytool"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ditto -c -k --keepParent \"$STAGED_APP\" \"$SUBMISSION_ZIP\""
else
  rm -f "$SUBMISSION_ZIP"
  ditto -c -k --keepParent "$STAGED_APP" "$SUBMISSION_ZIP"
fi

echo "==> notarytool submit"
NOTARY_KEY_ID="${SVNSTUDIO_NOTARY_KEY_ID:-${MACSVN_NOTARY_KEY_ID:-KEY_ID}}"
NOTARY_ISSUER="${SVNSTUDIO_NOTARY_ISSUER_ID:-${MACSVN_NOTARY_ISSUER_ID:-ISSUER_ID}}"
NOTARY_KEY_PATH="${SVNSTUDIO_NOTARY_KEY_PATH:-${MACSVN_NOTARY_KEY_PATH:-/path/to/AuthKey.p8}}"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] xcrun notarytool submit \"$SUBMISSION_ZIP\" --key-id $NOTARY_KEY_ID --issuer $NOTARY_ISSUER --key $NOTARY_KEY_PATH --wait --output-format json"
else
  xcrun notarytool submit "$SUBMISSION_ZIP" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --key "$NOTARY_KEY_PATH" \
    --wait \
    --output-format json >"$NOTARY_RESULT"
  /bin/cat "$NOTARY_RESULT"
  NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
  [[ "$NOTARY_STATUS" == "Accepted" ]] || {
    echo "error: 公证状态不是 Accepted: ${NOTARY_STATUS:-unknown}" >&2
    exit 1
  }
fi

echo "==> stapler staple"
run xcrun stapler staple "$STAGED_APP"
run xcrun stapler validate "$STAGED_APP"

echo "==> Gatekeeper 评估（本机）"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] spctl --assess --type execute --verbose=4 \"$STAGED_APP\""
else
  spctl --assess --type execute --verbose=4 "$STAGED_APP"
  "$ROOT/scripts/verify-release-app.sh" "$STAGED_APP"
fi

echo "==> 发布已通过闸门的最终应用"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] mv \"$STAGED_APP\" \"$FINAL_APP\""
else
  mv "$STAGED_APP" "$FINAL_APP"
fi

echo "==> 重新打包已 staple 的最终分发 ZIP"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ditto -c -k --keepParent \"$FINAL_APP\" \"$FINAL_ZIP_TEMP\""
  echo "[dry-run] mv \"$FINAL_ZIP_TEMP\" \"$FINAL_ZIP\""
else
  ditto -c -k --keepParent "$FINAL_APP" "$FINAL_ZIP_TEMP"
  mv "$FINAL_ZIP_TEMP" "$FINAL_ZIP"
fi

echo "==> 完成"
echo "产物: $FINAL_APP"
echo "归档: $FINAL_ZIP"
echo "请按 docs/acceptance/H1-manual-checklist.md「干净机冒烟」在未装 Xcode 的机器上验证。"
echo "bundle id 参考: $BUNDLE_ID"
