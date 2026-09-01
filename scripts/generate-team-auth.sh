#!/usr/bin/env bash
# Generates one memorable HTTP Basic Auth passphrase per team (team0 =
# organizer testing, team1-5 = event teams) plus one shared passphrase for
# the Open WebUI backup instance, hashes each with Caddy's own
# `hash-password` (bcrypt — what Caddyfile's `basic_auth` directive
# expects), writes the hashes into app/.env, and prints the plaintext
# passphrases to share with teams out-of-band (also saved to
# app/team-credentials.txt, gitignored — never commit it).
#
# Idempotent: a team whose *_BASIC_AUTH_HASH is already set in app/.env is
# left alone (its passphrase doesn't change on a re-run) — delete that one
# line from app/.env first if you deliberately want to rotate it. Needs
# Docker locally (to run caddy:2-alpine's hash-password), not the deployed
# stack — this can be run before the VM even exists.
#
# Usage: ./generate-team-auth.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

CREDENTIALS_FILE="$APP_DIR/team-credentials.txt"

# Small, deliberately unambiguous wordlist (no homophones, nothing that
# reads awkwardly spoken aloud at a kickoff) — passphrases are
# adjective-noun-NN, e.g. "quiet-harbor-42". Not trying to be
# cryptographically clever: this is a front-door gate against random
# internet traffic and casual credential sharing outside a team, not a
# defense against a targeted attacker, so memorability wins over entropy.
ADJECTIVES=(quiet swift bright calm bold amber coral azure violet golden
  brave clever gentle rapid silent steady sunny misty rustic vivid)
NOUNS=(harbor compass anchor voyage cargo beacon lantern current tide
  channel vessel cabin bridge signal horizon reef quay dock berth wharf)

random_passphrase() {
  local adj="${ADJECTIVES[$((RANDOM % ${#ADJECTIVES[@]}))]}"
  local noun="${NOUNS[$((RANDOM % ${#NOUNS[@]}))]}"
  local num=$((RANDOM % 90 + 10))
  echo "${adj}-${noun}-${num}"
}

hash_passphrase() {
  docker run --rm caddy:2-alpine caddy hash-password --plaintext "$1"
}

# CREDENTIALS_FILE holds one "username passphrase" line per team, built up
# across runs (bash 3.2 on macOS has no associative arrays, hence the
# plain-file approach rather than an in-memory map). Pre-existing lines
# survive a run that doesn't touch that team.
touch "$CREDENTIALS_FILE"

generate_one() {
  local username="$1" hash_var="$2"
  local existing
  existing="$(env_get "$hash_var")"
  if [ -n "$existing" ]; then
    echo "  $username: $hash_var already set in app/.env — skipping (unchanged)."
    return
  fi
  local passphrase
  passphrase="$(random_passphrase)"
  local hash
  hash="$(hash_passphrase "$passphrase")"
  env_set "$hash_var" "$hash"
  # Drop any stale line for this username (e.g. a hash was deleted from
  # .env by hand to force rotation) before appending the fresh one.
  grep -v "^$username " "$CREDENTIALS_FILE" > "$CREDENTIALS_FILE.tmp" 2>/dev/null || true
  mv "$CREDENTIALS_FILE.tmp" "$CREDENTIALS_FILE"
  echo "$username $passphrase" >> "$CREDENTIALS_FILE"
  echo "  $username: generated a new passphrase."
}

echo "Generating team Basic Auth passphrases..."
for n in "${TEAM_IDS[@]}"; do
  generate_one "team$n" "TEAM${n}_BASIC_AUTH_HASH"
done
generate_one "guest" "OPENWEBUI_BASIC_AUTH_HASH"

sort -o "$CREDENTIALS_FILE" "$CREDENTIALS_FILE"

echo
echo "Wrote hashes to $ENV_FILE."
echo "Wrote plaintext passphrases to $CREDENTIALS_FILE — share these with"
echo "teams out-of-band (slide/table tent at kickoff), never commit this file:"
echo
column -t "$CREDENTIALS_FILE" 2>/dev/null || cat "$CREDENTIALS_FILE"
echo
echo "Next: docker compose up -d caddy (or redeploy, on the VM) to pick up"
echo "the new hashes — Caddy env vars aren't hot-reloaded either."
