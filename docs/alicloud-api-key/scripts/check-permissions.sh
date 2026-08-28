#!/usr/bin/env bash
# Sanity-checks that the local `aliyun` profile can actually manage Model
# Studio (workspaces/keys). Run this first if any other script here fails
# with a 403 — it isolates whether it's a RAM permission gap.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

echo "--- aliyun CLI identity ---"
aliyun sts get-caller-identity

echo
echo "--- modelstudio plugin ---"
if ! aliyun modelstudio version >/dev/null 2>&1; then
  echo "Dedicated plugin not installed. Installing..."
  aliyun plugin install --names aliyun-cli-modelstudio
fi
aliyun modelstudio version

echo
echo "--- modelstudio:ListWorkspaces (region: $MS_REGION) ---"
if aliyun modelstudio list-workspaces --region "$MS_REGION"; then
  echo
  echo "OK — this identity can manage Model Studio."
else
  cat >&2 <<'EOF'

403 NoPermission here means the RAM user this `aliyun` profile authenticates
as doesn't have Model Studio permissions attached — separate from the
AliyunECSFullAccess/AliyunVPCFullAccess used for the infra/ Terraform side.

Fix: in the RAM console (https://ram.console.alibabacloud.com/users), open
the user this profile uses (`aliyun configure list` shows which), Permissions
tab -> Grant Permission -> attach `AliyunBailianControlFullAccess` (workspace/
account/API-key management; narrower than AliyunBailianFullAccess, which
adds data-layer permissions this project doesn't need).
EOF
  exit 1
fi
