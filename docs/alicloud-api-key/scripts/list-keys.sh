#!/usr/bin/env bash
# Lists API keys in the project's Model Studio workspace, with their
# enabled/disabled state and (masked) value — useful for confirming which
# key is currently live in app/.env, and for spotting stale test keys to
# clean up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

aliyun modelstudio list-api-keys --region "$MS_REGION" --workspace-id "$MS_WORKSPACE_ID"
