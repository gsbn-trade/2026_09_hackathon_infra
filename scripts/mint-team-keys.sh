#!/usr/bin/env bash
# Mints the full set of per-team LiteLLM virtual keys this deployment needs
# — one bolt.diy key and one DeepSeek Harness key per team (team0 =
# organizer testing, team1-5 = event teams), each under its own LiteLLM
# team_id so spend/budget aggregates per team across both keys — and writes
# them into app/.env. Automates README step 5's manual curl, twelve times
# over, instead of by hand. Also applies per-team, per-model TPM/RPM caps
# (MODEL_TPM_LIMIT/MODEL_RPM_LIMIT below) to every team, new or existing —
# see litellm-config.yaml's rate-limit comment for why these exist and how
# the numbers were chosen (real Bailian account limits hit live 2026-09-03).
#
# Idempotent for keys: a team whose TEAMn_VIRTUAL_KEY / TEAMn_DSH_VIRTUAL_KEY
# is already set in app/.env is left alone — re-running this after minting
# some teams only fills in the rest. Regenerating a key would invalidate
# the old one for whichever container already has it baked in, which is
# exactly what idempotency here is protecting against once teams are live.
# Rate limits are NOT gated by that same check, on purpose — re-running this
# always (re)applies the current MODEL_TPM_LIMIT/MODEL_RPM_LIMIT to every
# team via /team/update, so tightening/loosening a limit later just means
# editing the values below and re-running, no key rotation involved.
#
# Usage: ./mint-team-keys.sh [base-url]
#   default base-url: http://localhost:4000 (local docker compose)
#   for the cloud deploy:                    https://gateway.<your-domain>
#
# Env overrides:
#   TEAM_BUDGET   max_budget (USD) per event team (team1-5). Default: 100
#                 (raised from 20 on 2026-09-03, the same day cost tracking
#                 started actually working — see litellm-config.yaml's
#                 pricing comment. Before that, max_budget couldn't trigger
#                 at all regardless of its value, so $20 had never been a
#                 real ceiling; $100 is deliberately generous now that it
#                 is one — team5's heaviest day so far, ~15.8M tokens
#                 mostly on deepseek-v4-flash-0731, comes to roughly $7 at
#                 that model's peak rate, for scale.)
#   TEAM0_BUDGET  max_budget (USD) for team0 (organizer testing). Default: 20
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

BASE_URL="${1:-http://localhost:4000}"
: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in app/.env}"
TEAM_BUDGET="${TEAM_BUDGET:-100}"
TEAM0_BUDGET="${TEAM0_BUDGET:-20}"

# Matches app/litellm-config.yaml's model_list exactly. dsh's own model
# roster (app/deepseek-harness/home/settings.yaml) deliberately drops
# kimi-k2.7-code — bolt.diy is the coding track, the other four cover what
# DeepSeek Harness needs (see ARCHITECTURE.md's Model sourcing table) — so
# its keys are scoped to only those four, on top of bolt.diy's key already
# being scoped to all five.
BOLT_MODELS='["qwen3.8-flash","deepseek-v4-flash-0731","deepseek-v4-pro-0813","kimi-k2.7-code","glm-5.2"]'
DSH_MODELS='["qwen3.8-flash","deepseek-v4-flash-0731","deepseek-v4-pro-0813","glm-5.2"]'

# Per-team TPM/RPM ceilings, aggregated by LiteLLM across BOTH of a team's
# keys (bolt.diy + dsh) since they share one team_id — sized off Bailian's
# real Hong Kong account-wide limits (see litellm-config.yaml's rate-limit
# comment for the source and numbers), at roughly 60-65% of an even 5-way
# split so 5 teams going at once land around 60-75% of the account ceiling,
# not 100%+. Goal: make one team's burst throttle *that team* well before it
# can trip the shared account limit for everyone else (which is what
# actually happened 2026-09-03 — see litellm-config.yaml's fallback comment)
# — this is the first line of defense; `default_fallbacks: ["qwen3.8-flash"]`
# in litellm-config.yaml is the second, for whenever the shared limit gets
# hit anyway. qwen3.8-flash itself is deliberately NOT capped here — it's
# the fallback target, so throttling it would undermine the whole point.
MODEL_TPM_LIMIT='{"deepseek-v4-flash-0731":150000,"deepseek-v4-pro-0813":150000,"glm-5.2":120000,"kimi-k2.7-code":120000}'
MODEL_RPM_LIMIT='{"deepseek-v4-flash-0731":2000,"deepseek-v4-pro-0813":2000,"glm-5.2":60,"kimi-k2.7-code":60}'

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
  response="$(api_post "/team/new" "{\"team_id\":\"$team_id\",\"max_budget\":$budget,\"models\":$BOLT_MODELS,\"model_tpm_limit\":$MODEL_TPM_LIMIT,\"model_rpm_limit\":$MODEL_RPM_LIMIT}")"
  body="$(echo "$response" | sed '$d')"
  code="$(echo "$response" | tail -1)"
  if [ "$code" = "200" ]; then
    echo "  team $team_id: created (budget \$$budget, rate limits applied)."
    return
  fi
  # Most common non-200 here is "team already exists" from a prior run.
  # /team/new won't retroactively apply new fields (rate limits included) to
  # a team that already exists — /team/update does, and is safe to call
  # unconditionally every run (it's a real update, not create-once), which
  # is how already-live teams (this repo's actual team0-5, created before
  # per-model rate limits existed) pick up MODEL_TPM_LIMIT/MODEL_RPM_LIMIT
  # without needing a separate one-off script.
  echo "  team $team_id: /team/new returned HTTP $code (probably already exists) — applying rate limits via /team/update instead."
  response="$(api_post "/team/update" "{\"team_id\":\"$team_id\",\"model_tpm_limit\":$MODEL_TPM_LIMIT,\"model_rpm_limit\":$MODEL_RPM_LIMIT}")"
  body="$(echo "$response" | sed '$d')"
  code="$(echo "$response" | tail -1)"
  if [ "$code" = "200" ]; then
    echo "  team $team_id: rate limits updated."
  else
    echo "  team $team_id: /team/update FAILED (HTTP $code) — $body" >&2
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
