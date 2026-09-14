#!/usr/bin/env bash
# Safely restarts one or more DeepSeek Harness teams on the live VM —
# "safely" meaning it always recreates a team's main container *and* its
# -proxy sidecar together, never one alone.
#
# Why this exists (real incident, 2026-09-03): `deepseek-harness-teamN-proxy`
# uses `network_mode: "service:deepseek-harness-teamN"` in docker-compose.yml
# — it shares the main container's network namespace, because dsh itself
# only binds to 127.0.0.1 by design (see docker-compose.yml's own comment on
# that container). `docker compose restart deepseek-harness-teamN` alone
# recreates that container's network namespace but leaves the never-touched
# -proxy sidecar attached to the old, now-gone one — Caddy's front door then
# gets "connection refused" on that team's whole subdomain until the proxy
# is *also* recreated. This took all six teams down for ~30 minutes before
# being caught. `docker compose restart` on the proxy alone doesn't fix it
# either — `network_mode: service:X` is only resolved at container-creation
# time, so the proxy container must be recreated (`up -d --force-recreate`),
# not merely restarted.
#
# No SSH from this operator's Mac (JumpCloud EndpointSecurity blocks the SSH
# protocol outright — TCP connects fine, but the banner exchange never
# completes), so this drives the VM via `aliyun ecs RunCommand` (Cloud
# Assistant) instead.
#
# Usage:
#   scripts/restart-dsh-team.sh 0 2 5     # just teams 0, 2, 5
#   scripts/restart-dsh-team.sh all       # every team, 0-5
#
# Requires: `aliyun` CLI configured, and `tofu -chdir=infra output` working
# (reads the instance id from there instead of hardcoding it).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <team-number> [team-number ...] | all" >&2
  exit 1
fi

if [ "$1" == "all" ]; then
  TEAMS=(0 1 2 3 4 5)
else
  TEAMS=("$@")
fi

INSTANCE_ID=$(tofu -chdir="$REPO_ROOT/infra" output -raw instance_id)
REGION="cn-hongkong"

SERVICES=""
for t in "${TEAMS[@]}"; do
  SERVICES="$SERVICES deepseek-harness-team${t} deepseek-harness-team${t}-proxy"
done

echo "Restarting on $INSTANCE_ID:$SERVICES"

CMD="cd /opt/app && docker compose up -d --force-recreate$SERVICES"
B64=$(printf '%s' "$CMD" | base64)

INVOKE_ID=$(aliyun ecs RunCommand --region "$REGION" --Type RunShellScript --Timeout 180 \
  --InstanceId.1 "$INSTANCE_ID" \
  --CommandContent "$B64" --ContentEncoding Base64 \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["InvokeId"])')

echo "Invoke: $INVOKE_ID (polling)..."
for _ in $(seq 1 30); do
  sleep 2
  RESULT=$(aliyun ecs DescribeInvocationResults --region "$REGION" --InvokeId "$INVOKE_ID")
  STATUS=$(echo "$RESULT" | python3 -c 'import json,sys; d=json.load(sys.stdin)["Invocation"]["InvocationResults"]["InvocationResult"][0]; print(d["InvokeRecordStatus"])')
  if [ "$STATUS" == "Finished" ]; then
    echo "$RESULT" | python3 -c '
import json, sys, base64
d = json.load(sys.stdin)["Invocation"]["InvocationResults"]["InvocationResult"][0]
print("Exit code:", d["ExitCode"])
print(base64.b64decode(d["Output"]).decode(errors="replace"))
'
    break
  fi
done

echo
echo "Verifying externally (expect 200 or 401, never 502/000):"
for t in "${TEAMS[@]}"; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 15 "https://team${t}.hack.gsbn.trade/" || echo "000")
  echo "  team${t} -> $code"
done
