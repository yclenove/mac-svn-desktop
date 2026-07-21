#!/usr/bin/env bash
# 检查签名/公证前置工具与环境变量（V4）。
# 优先 SVNSTUDIO_*，兼容旧 MACSVN_*。
set -euo pipefail

DRY_RUN="${SVNSTUDIO_DRY_RUN:-${MACSVN_DRY_RUN:-0}}"
APP_PATH="${SVNSTUDIO_APP_PATH:-${MACSVN_APP_PATH:-}}"
SIGN_IDENTITY="${SVNSTUDIO_SIGN_IDENTITY:-${MACSVN_SIGN_IDENTITY:-}}"
NOTARY_KEY_PATH="${SVNSTUDIO_NOTARY_KEY_PATH:-${MACSVN_NOTARY_KEY_PATH:-}}"
NOTARY_KEY_ID="${SVNSTUDIO_NOTARY_KEY_ID:-${MACSVN_NOTARY_KEY_ID:-}}"
NOTARY_ISSUER_ID="${SVNSTUDIO_NOTARY_ISSUER_ID:-${MACSVN_NOTARY_ISSUER_ID:-}}"

fail() { echo "verify-signing-prereqs: $*" >&2; exit 1; }
ok() { echo "verify-signing-prereqs: $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"
}

need_cmd codesign
need_cmd ditto
need_cmd xcrun
need_cmd spctl

if ! xcrun --find notarytool >/dev/null 2>&1; then
  fail "找不到 notarytool（请安装 Xcode / CLT）"
fi
if ! xcrun --find stapler >/dev/null 2>&1; then
  fail "找不到 stapler"
fi

ok "工具链可用（codesign / notarytool / stapler / spctl）"

if [[ "$DRY_RUN" == "1" ]]; then
  ok "SVNSTUDIO_DRY_RUN=1：跳过密钥与证书存在性检查"
  exit 0
fi

[[ -n "$SIGN_IDENTITY" ]] || fail "未设置 SVNSTUDIO_SIGN_IDENTITY"
[[ -n "$APP_PATH" ]] || fail "未设置 SVNSTUDIO_APP_PATH"
[[ -d "$APP_PATH" ]] || fail "SVNSTUDIO_APP_PATH 不是目录: $APP_PATH"
case "$SIGN_IDENTITY" in
  "Developer ID Application:"*) ;;
  *) fail "签名身份必须是 Developer ID Application: $SIGN_IDENTITY" ;;
esac

if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
  fail "当前钥匙串未匹配到签名身份: $SIGN_IDENTITY"
fi

if [[ -n "$NOTARY_KEY_PATH" ]]; then
  [[ -f "$NOTARY_KEY_PATH" ]] || fail "SVNSTUDIO_NOTARY_KEY_PATH 不存在: $NOTARY_KEY_PATH"
  [[ -n "$NOTARY_KEY_ID" ]] || fail "未设置 SVNSTUDIO_NOTARY_KEY_ID"
  [[ -n "$NOTARY_ISSUER_ID" ]] || fail "未设置 SVNSTUDIO_NOTARY_ISSUER_ID"
  ok "API Key 公证凭据路径检查通过"
else
  fail "未设置 SVNSTUDIO_NOTARY_KEY_PATH"
fi

ok "前置检查通过"
