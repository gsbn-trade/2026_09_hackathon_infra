#!/bin/bash
# Bootstraps Docker only. No app files and no secrets go through user_data —
# those are pushed later over SSH by ../deploy.sh, so nothing sensitive sits
# in AliCloud's instance metadata/console.
set -euo pipefail

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
mkdir -p /opt/app

# 8GB swap: cheap insurance against a memory spike (e.g. several bolt.diy
# instances generating at once) OOM-killing a container instead of just
# slowing down — and this stack was explicitly told latency doesn't matter,
# so occasional swapping is a fine trade for not losing a team's session.
# Idempotent: skips if a swapfile already exists (re-running cloud-init, or
# applying this after the fact).
if [ ! -f /swapfile ]; then
  fallocate -l 8G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
