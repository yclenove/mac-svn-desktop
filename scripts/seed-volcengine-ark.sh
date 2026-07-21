#!/usr/bin/env bash
# 将火山方舟 Coding API 写入本机 SVN Studio Application Support + Keychain。
# 用法：ARK_API_KEY=... ./scripts/seed-volcengine-ark.sh
# 密钥不会写入仓库；仅落本机 Keychain。

set -euo pipefail

ARK_API_KEY="${ARK_API_KEY:-}"
if [[ -z "$ARK_API_KEY" ]]; then
  echo "缺少 ARK_API_KEY 环境变量" >&2
  exit 1
fi

BASE_URL="${ARK_BASE_URL:-https://ark.cn-beijing.volces.com/api/coding/v3}"
MODEL="${ARK_MODEL:-doubao-seed-code}"
SUPPORT="${HOME}/Library/Application Support/SVNStudio"
PROVIDERS_FILE="${SUPPORT}/ai-providers.json"
PROVIDER_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
ACCOUNT="$PROVIDER_ID"
REF="svnstudio.ai-provider.${PROVIDER_ID}"

mkdir -p "$SUPPORT"

security delete-generic-password -s "SVNStudio.AIProvider" -a "$ACCOUNT" >/dev/null 2>&1 || true
security add-generic-password -s "SVNStudio.AIProvider" -a "$ACCOUNT" -w "$ARK_API_KEY" -U

PROVIDERS_FILE="$PROVIDERS_FILE" PROVIDER_ID="$PROVIDER_ID" BASE_URL="$BASE_URL" MODEL="$MODEL" REF="$REF" python3 <<'PY'
import json, os
from pathlib import Path
path = Path(os.environ["PROVIDERS_FILE"])
provider_id = os.environ["PROVIDER_ID"]
provider = {
    "id": provider_id,
    "name": "火山方舟 Coding",
    "kind": "openAICompatible",
    "baseURL": os.environ["BASE_URL"],
    "model": os.environ["MODEL"],
    "apiKeyRef": os.environ["REF"],
    "maxTokens": 4096,
    "temperature": 0.2,
}
data = {"version": 1, "providers": [provider], "defaultProviderID": provider_id}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"已写入 {path}")
print(f"defaultProviderID={provider_id}")
print(f"model={os.environ['MODEL']}")
print("API Key 仅存 Keychain，未写入 JSON。")
PY
