#!/usr/bin/env bash
# Checks connectivity one layer up from smoke-test-provider.sh: LiteLLM's
# own /health endpoint, which makes a real test request to every model in
# litellm-config.yaml through LiteLLM itself (not just "is the process up"
# like /health/liveliness). Run smoke-test-provider.sh first — if that
# fails, this will too, and the provider script's error is more direct.
#
# Usage: ./smoke-test-litellm.sh [base-url]
#   default base-url: http://localhost:4000 (local docker compose)
#   for the cloud deploy:                    https://gateway.<your-domain>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

BASE_URL="${1:-http://localhost:4000}"
: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in app/.env}"

echo "GET $BASE_URL/health"
echo

RESPONSE=$(curl -s -w '\n%{http_code}' "$BASE_URL/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY")
BODY=$(echo "$RESPONSE" | sed '$d')
CODE=$(echo "$RESPONSE" | tail -1)

echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
echo
echo "HTTP $CODE"

UNHEALTHY=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("unhealthy_count", "?"))' 2>/dev/null || echo "?")

if [ "$CODE" = "200" ] && [ "$UNHEALTHY" = "0" ]; then
  echo "PASS — LiteLLM can reach every configured model."
else
  echo
  echo "FAIL or degraded (unhealthy_count=$UNHEALTHY). Check unhealthy_endpoints[].error above." >&2
  echo "If litellm-config.yaml or app/.env changed recently, remember env vars/mounted" >&2
  echo "config aren't hot-reloaded: docker compose restart litellm (local) or" >&2
  echo "redeploy (cloud) before assuming the key itself is broken." >&2
  exit 1
fi
