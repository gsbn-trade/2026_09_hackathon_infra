#!/usr/bin/env bash
# Mints the full set of per-team LiteLLM virtual keys this deployment needs
# — one bolt.diy key and one DeepSeek Harness key per team (team0 =
# organizer testing, team1-5 = event teams), each under its own LiteLLM
# team_id so spend/budget aggregates per team across both keys — and writes
# them into app/.env. Automates README step 5's manual curl, twelve times
# over, instead of by hand.
#
# Idempotent: a team whose TEAMn_VIRTUAL_KEY / TEAMn_DSH_VIRTUAL_KEY is
# already set in app/.env is left alone — re-running this after minting
# some teams only fills in the rest. Regenerating a key would invalidate
# the old one for whichever container already has it baked in, which is
# exactly what idempotency here is protecting against once teams are live.
#
# Usage: ./mint-team-keys.sh [base-url]
#   default base-url: http://localhost:4000 (local docker compose)
#   for the cloud deploy:                    https://gateway.<your-domain>
#
# Env overrides:
#   TEAM_BUDGET   max_budget (USD) per event team (team1-5). Default: 20
#   TEAM0_BUDGET  max_budget (USD) for team0 (organizer testing). Default: 5
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

BASE_URL="${1:-http://localhost:4000}"
: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in app/.env}"
TEAM_BUDGET="${TEAM_BUDGET:-20}"
TEAM0_BUDGET="${TEAM0_BUDGET:-5}"

# Matches app/litellm-config.yaml's model_list exactly. dsh's own model
# roster (app/deepseek-harness/home/settings.yaml) deliberately drops
# kimi-k2.7-code — bolt.diy is the coding track, the other four cover what
# DeepSeek Harness needs (see ARCHITECTURE.md's Model sourcing table) — so
# its keys are scoped to only those four, on top of bolt.diy's key already
# being scoped to all five.
BOLT_MODELS='["qwen3.8-flash","deepseek-v4-flash-0731","deepseek-v4-pro-0813","kimi-k2.7-code","glm-5.2"]'
DSH_MODELS='["qwen3.8-flash","deepseek-v4-flash-0731","deepseek-v4-pro-0813","glm-5.2"]'

api_post() {
  local path="$1" body="$2"
  curl -sS -w '\n%{http_code}' "$BASE_URL$path" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$body"
}

extract_field() {
  # $1: JSON body, $2: field name. Empty string if missing/unparseable.
  python3 -c '
import sys, json
try:
    print(json.loads(sys.argv[1]).get(sys.argv[2], "") or "")
except Exception:
    print("")
' "$1" "$2"
}

ensure_team() {
  local team_id="$1" budget="$2"
  local response body code
  response="$(api_post "/team/new" "{\"team_id\":\"$team_id\",\"max_budget\":$budget,\"models\":$BOLT_MODELS}")"
  body="$(echo "$response" | sed '$d')"
  code="$(echo "$response" | tail -1)"
  if [ "$code" = "200" ]; then
    echo "  team $team_id: created (budget \$$budget)."
  else
    # Most common non-200 here is "team already exists" from a prior run —
    # harmless, the team is already there with whatever budget it was
    # created with. Anything else surfaces below when key minting fails too.
    echo "  team $team_id: /team/new returned HTTP $code (probably already exists) — continuing."
  fi
}

mint_key() {
  local team_id="$1" alias="$2" models="$3" env_var="$4"
  local existing
  existing="$(env_get "$env_var")"
  if [ -n "$existing" ]; then
    echo "  $alias: $env_var already set in app/.env — skipping (unchanged)."
    return
  fi
  local response body code key
  response="$(api_post "/key/generate" "{\"team_id\":\"$team_id\",\"key_alias\":\"$alias\",\"models\":$models}")"
  body="$(echo "$response" | sed '$d')"
  code="$(echo "$response" | tail -1)"
  if [ "$code" != "200" ]; then
    echo "  $alias: FAILED (HTTP $code) — $body" >&2
    return 1
  fi
  key="$(extract_field "$body" key)"
  if [ -z "$key" ]; then
    echo "  $alias: FAILED — HTTP 200 but no 'key' field in response: $body" >&2
    return 1
  fi
  env_set "$env_var" "$key"
  echo "  $alias: minted, written to $env_var."
}

echo "Target: $BASE_URL"
echo

for n in "${TEAM_IDS[@]}"; do
  team_id="team$n"
  budget="$TEAM_BUDGET"
  [ "$n" = "0" ] && budget="$TEAM0_BUDGET"
  echo "--- $team_id ---"
  ensure_team "$team_id" "$budget"
  mint_key "$team_id" "${team_id}-boltdiy" "$BOLT_MODELS" "TEAM${n}_VIRTUAL_KEY"
  mint_key "$team_id" "${team_id}-dsh" "$DSH_MODELS" "TEAM${n}_DSH_VIRTUAL_KEY"
done

echo
echo "Done. Redeploy (or 'docker compose up -d' the affected boltdiy-teamN /"
echo "deepseek-harness-teamN services) to pick up newly minted keys — env"
echo "vars aren't hot-reloaded."
