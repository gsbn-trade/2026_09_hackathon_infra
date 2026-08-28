#!/usr/bin/env bash
# Mints a new Model Studio API key in the project's workspace.
#
# Usage: ./create-key.sh "description of why this key exists"
#
# The key value is only ever shown once, right here — Alibaba doesn't let
# you retrieve it again later (list-keys.sh only ever shows a masked
# version). Copy it into app/.env's DASHSCOPE_API_KEY yourself; this script
# deliberately doesn't write to .env for you.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

DESCRIPTION="${1:?Usage: $0 \"description\"}"

aliyun modelstudio create-api-key \
  --region "$MS_REGION" \
  --workspace-id "$MS_WORKSPACE_ID" \
  --description "$DESCRIPTION"

cat <<EOF

^ apiKeyValue above is shown once — copy it now.

Next:
  1. Paste it into app/.env as DASHSCOPE_API_KEY (replacing the old value).
  2. cd app && docker compose restart litellm   # env vars aren't hot-reloaded
  3. ./smoke-test-provider.sh                   # confirm it actually works
EOF
