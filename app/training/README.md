# Training materials

Shared reference material, identical for every team — not generated
per-team content like `deepseek-harness/workspace-teamN/` is.

Served read-only at `https://teamN.hack.gsbn.trade/training/` (same Basic
Auth as the rest of that team's subdomain — no separate passphrase) via the
`/training/*` static browser in `../Caddyfile`, backed by the single shared
`./training:/srv/training:ro` mount in `../docker-compose.yml` (see either
file's comment for why this is one shared mount rather than the six
per-team ones `/files/*` uses).

## Updating

Add, replace, or remove files directly in this directory and redeploy
(`git push` + `./deploy.sh`, or `../scripts/restart-dsh-team.sh` if only a
team's harness needs recreating). No container restart needed for content
changes — Caddy serves this directory's live contents on every request. A
restart is only needed once, when the `/training/*` *route* itself is added
or changed in `../Caddyfile`.

## Contents

- `1 - SMDG Training.pdf`
- `2 - SMDG Vibeathon - howto.pdf`
