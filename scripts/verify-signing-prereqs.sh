#!/usr/bin/env bash
# 检查签名/公证前置工具与环境变量（V4）。
set -euo pipefail

DRY_RUN="${MACSVN_DRY_RUN:-0}"
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
  ok "MACSVN_DRY_RUN=1：跳过密钥与证书存在性检查"
  exit 0
fi

[[ -n "${MACSVN_SIGN_IDENTITY:-}" ]] || fail "未设置 MACSVN_SIGN_IDENTITY"
[[ -n "${MACSVN_APP_PATH:-}" ]] || fail "未设置 MACSVN_APP_PATH"
[[ -d "${MACSVN_APP_PATH}" ]] || fail "MACSVN_APP_PATH 不是目录: $MACSVN_APP_PATH"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "$MACSVN_SIGN_IDENTITY" >/dev/null; then
  echo "verify-signing-prereqs: 警告：当前钥匙串未匹配到身份（仍可继续，若证书在其他钥匙串请忽略）" >&2
fi

if [[ -n "${MACSVN_NOTARY_KEY_PATH:-}" ]]; then
  [[ -f "$MACSVN_NOTARY_KEY_PATH" ]] || fail "MACSVN_NOTARY_KEY_PATH 不存在: $MACSVN_NOTARY_KEY_PATH"
  [[ -n "${MACSVN_NOTARY_KEY_ID:-}" ]] || fail "未设置 MACSVN_NOTARY_KEY_ID"
  [[ -n "${MACSVN_NOTARY_ISSUER_ID:-}" ]] || fail "未设置 MACSVN_NOTARY_ISSUER_ID"
  ok "API Key 公证凭据路径检查通过"
else
  fail "未设置 MACSVN_NOTARY_KEY_PATH（或改用文档中的 Apple ID 方式自行扩展脚本）"
fi

ok "前置检查通过"
