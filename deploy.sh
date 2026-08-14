#!/usr/bin/env bash
# Pushes app/ to the VM tofu provisioned and (re)starts the stack.
# Safe to re-run any time you change litellm-config.yaml, Caddyfile, or .env.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f app/.env ]; then
  echo "app/.env not found. Copy app/.env.example to app/.env and fill in real values first." >&2
  exit 1
fi

IP=$(tofu -chdir=infra output -raw public_ip)
echo "Target: root@${IP}"

ssh -o StrictHostKeyChecking=accept-new root@"${IP}" "mkdir -p /opt/app"
rsync -avz --exclude '.env' app/ root@"${IP}":/opt/app/
scp app/.env root@"${IP}":/opt/app/.env
ssh root@"${IP}" "cd /opt/app && docker compose pull && docker compose up -d"

echo
echo "Deployed. Once DNS for your domain points at ${IP}:"
echo "  LiteLLM gateway:  https://gateway.<your-domain>"
echo "  bolt.diy:         https://build.<your-domain>"
