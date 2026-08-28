#!/usr/bin/env bash
# Shared by the other scripts in this directory — not meant to be run
# directly. Loads app/.env without printing it, and sets the project's
# Model Studio defaults (override via env vars if these ever change).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$REPO_ROOT/app/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy app/.env.example to app/.env and fill it in first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${MS_REGION:=cn-hongkong}"
: "${MS_WORKSPACE_ID:=ws-rhuu77n0pee2tjts}"
MS_API_BASE="https://${MS_WORKSPACE_ID}.${MS_REGION}.maas.aliyuncs.com/compatible-mode/v1"

: "${DASHSCOPE_API_KEY:?DASHSCOPE_API_KEY not set in app/.env}"
