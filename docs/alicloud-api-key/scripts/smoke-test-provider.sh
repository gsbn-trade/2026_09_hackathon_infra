#!/usr/bin/env bash
# Calls Model Studio directly with the key from app/.env — bypasses LiteLLM,
# Docker, and bolt.diy entirely. This is the cheapest layer to test at: a
# 200 here means the key + workspace + endpoint are all correct, full stop.
# Any failure is a provider-side problem, not something in this repo's stack.
#
# Usage: ./smoke-test-provider.sh [model-id]   (default: qwen3.8-flash)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

MODEL="${1:-qwen3.8-flash}"

echo "POST $MS_API_BASE/chat/completions"
echo "model: $MODEL"
echo

RESPONSE=$(curl -s -w '\n%{http_code}' "$MS_API_BASE/chat/completions" \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly one word: PONG\"}],\"max_tokens\":10}")

BODY=$(echo "$RESPONSE" | sed '$d')
CODE=$(echo "$RESPONSE" | tail -1)

echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
echo
echo "HTTP $CODE"

if [ "$CODE" = "200" ]; then
  echo "PASS — key, workspace, and endpoint are all correct."
else
  cat >&2 <<EOF

FAIL. Common causes for this project (see ../README.md for the full table):
  401 invalid_api_key           -> key/endpoint region mismatch, or key
                                    revoked/disabled (check list-keys.sh)
  400 BadRequest.EmptyWorkspace -> wrong path; must be /compatible-mode/v1,
                                    not /api/v1 (check MS_API_BASE above)
  403                           -> RAM permissions gap; run
                                    check-permissions.sh
EOF
  exit 1
fi
