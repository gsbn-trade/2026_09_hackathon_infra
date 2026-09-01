#!/usr/bin/env bash
# Registers /workspace as each team's DeepSeek Harness workspace — without
# this, a fresh instance shows "no workspace configured" with no presets,
# and the UI's own "Select Workspace Directory" button fails with
# `transport failure for /api/host.listDirectory: HTTP 403` (a deliberate
# upstream loopback/same-origin restriction on the directory-*browsing*
# API — see docs/deepseek-harness/README.md's Known quirks). This uses the
# separate, unrestricted workspace.create RPC instead, called from inside
# each container (genuinely loopback, so the restriction never applies
# regardless).
#
# Safe to run any time, on any subset of teams: workspace.create is
# idempotent (a path already owned by a workspace just comes back with
# created: false, not an error) — re-running after seeding some teams only
# affects the ones that still need it. Needs no LiteLLM/gateway
# reachability, no `aliyun` CLI, no SSH — this is meant to run *on* the VM
# itself (over Cloud Assistant's RunCommand, or directly if you have a
# working shell on the box), since it talks to each container's own
# loopback.
#
# Usage: ./seed-dsh-workspaces.sh [team-id ...]
#   no args: seeds team0 through team5
#   with args: seeds only the teams named, e.g. ./seed-dsh-workspaces.sh 2 3
set -euo pipefail

TEAMS=("$@")
if [ ${#TEAMS[@]} -eq 0 ]; then
  TEAMS=(0 1 2 3 4 5)
fi

for n in "${TEAMS[@]}"; do
  CONTAINER="hackathon-deepseek-harness-team${n}-1"
  echo "--- team$n ($CONTAINER) ---"
  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "  container not found — skipping (is team$n running?)" >&2
    continue
  fi
  docker exec "$CONTAINER" node -e "
    const body = JSON.stringify({
      type: 'client-request',
      rpcId: 'seed-workspace-team${n}',
      method: 'workspace.create',
      payload: {path: '/workspace'},
    });
    fetch('http://127.0.0.1:3080/api/workspace.create', {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body,
    }).then(async (r) => {
      const text = await r.text();
      console.log(r.status, text);
      if (r.status !== 200) process.exitCode = 1;
    }).catch((e) => {
      console.error('request failed:', e);
      process.exitCode = 1;
    });
  "
done
