#!/usr/bin/env bash
# Lists Model Studio workspaces visible to this aliyun profile. Useful for
# confirming the workspace ID/region baked into _env.sh (MS_WORKSPACE_ID /
# MS_REGION) still matches what's actually in the account, and for finding
# each workspace's own dedicated apiHost.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

aliyun modelstudio list-workspaces --region "$MS_REGION"
