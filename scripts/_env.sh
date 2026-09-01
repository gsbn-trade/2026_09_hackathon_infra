#!/usr/bin/env bash
# Shared by the other scripts in this directory — not meant to be run
# directly. Loads app/.env without printing it (same pattern as
# docs/alicloud-api-key/scripts/_env.sh, one level up in this repo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
ENV_FILE="$APP_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy app/.env.example to app/.env and fill it in first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Every team id this project provisions for — team0 is organizer testing
# only (see docker-compose.yml's "organizer" profile), team1-5 are the
# actual event teams.
TEAM_IDS=(0 1 2 3 4 5)

# Upserts NAME=VALUE in ENV_FILE: replaces an existing `NAME=...` line in
# place, or appends a new one — used instead of sed so this behaves
# identically on macOS (BSD sed) and Linux (GNU sed), which was a real
# pitfall elsewhere in this repo's history.
#
# Always writes the value single-quoted (NAME='value'). Every value written
# here so far (LiteLLM keys, hex secrets) would work unquoted too, but
# bcrypt hashes (generate-team-auth.sh) contain literal `$` — and this
# file's own loader below does a real `source`, i.e. bash itself parses it,
# so an unquoted `$2a$14$...` gets expanded as positional parameters
# ($2, $14, ...) instead of being kept literal. Single-quoting is what makes
# `source` treat the value as inert text; docker compose's own .env parser
# handles single-quoted values correctly too (quotes stripped, no further
# expansion), so this is safe for both readers.
env_set() {
  local name="$1" value="$2"
  python3 - "$ENV_FILE" "$name" "$value" <<'PY'
import sys
path, name, value = sys.argv[1:4]
with open(path) as f:
    lines = f.readlines()
prefix = name + "="
new_line = f"{name}='{value}'\n"
found = False
for i, line in enumerate(lines):
    if line.startswith(prefix):
        lines[i] = new_line
        found = True
        break
if not found:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(new_line)
with open(path, "w") as f:
    f.writelines(lines)
PY
}

# Reads NAME's current value out of ENV_FILE (empty string if unset/blank) —
# used to decide whether a key/passphrase already exists before generating
# a new one, so re-running these scripts is safe.
env_get() {
  local name="$1"
  python3 - "$ENV_FILE" "$name" <<'PY'
import sys
path, name = sys.argv[1:3]
prefix = name + "="
with open(path) as f:
    for line in f:
        if line.startswith(prefix):
            value = line[len(prefix):].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            print(value)
            break
    else:
        print("")
PY
}
