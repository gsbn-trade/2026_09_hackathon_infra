# Rate limits and quotas: account-wide vs. per-team

Single reference for both layers of rate limiting in this deployment.
Detailed reasoning lives with the config that enforces each layer — this
page is the at-a-glance table, not a replacement for those comments.

## Two layers

1. **Account-wide** — a hard ceiling from Alibaba Cloud Bailian/Model
   Studio, shared across every team/key on this account. LiteLLM has no
   control over this; if the *sum* of all teams' real traffic exceeds it,
   Bailian itself starts rejecting calls ("Allocated quota exceeded" — what
   actually happened live, 2026-09-03, on the two DeepSeek models). Source
   and caveats: `app/litellm-config.yaml`'s top-of-file comment.
2. **Per-team** — a LiteLLM-enforced ceiling per `team_id`, aggregated
   across that team's two keys (bolt.diy + DeepSeek Harness). Exists so one
   team's bug/burst throttles *that team* well before it can push the
   account-wide sum over the real ceiling above. Source and reasoning:
   `scripts/mint-team-keys.sh`'s `MODEL_TPM_LIMIT`/`MODEL_RPM_LIMIT`.

Per-team caps are set at **16% of that model's own account-wide ceiling**
(2026-09-04) — same rule for both TPM and RPM. 16% means the 5 real event
teams (team1-5) going flat-out simultaneously land at 80% of each model's
account-wide ceiling, leaving ~20% headroom for team0 (organizer testing —
lighter but non-zero real usage, not excluded from the pool) plus the fact
that real traffic isn't perfectly smooth/non-overlapping within any given
60-second window.

## Quota table

| Model | Account TPM | Team TPM (16%) | Account RPM | Team RPM (16%) |
|---|---:|---:|---:|---:|
| `qwen3.8-flash` | 2,500,000 | 400,000 | 15,000 | 2,400 |
| `deepseek-v4-flash-0731` | 1,200,000 | 192,000 | 15,000 | 2,400 |
| `deepseek-v4-pro-0813` | 1,200,000 | 192,000 | 15,000 | 2,400 |
| `glm-5.2` | 1,000,000 | 160,000 | 500 | 80 |
| `kimi-k2.7-code` | 1,000,000 | 160,000 | 500 | 80 |

Same per-team caps apply identically to every team, team0 through team5 —
there's no per-team variation today. `kimi-k2.7-code` is bolt.diy-only
(deliberately excluded from DeepSeek Harness's own model list — see
`app/deepseek-harness/home/settings.yaml`'s comment) but the team-level cap
above still applies to it, since bolt.diy and dsh share one `team_id`.

`qwen3.8-flash` is also every model's `default_fallbacks` target
(`app/litellm-config.yaml`) and, since 2026-09-04, every team's own default
model too (`app/deepseek-harness/home*/settings.yaml`) — it's the one model
with nowhere further to fall back to, which is why it gets its own per-team
cap rather than being left uncapped as a fallback-of-last-resort.

## Where these numbers actually live (source of truth)

- **Account-wide ceilings + per-token pricing**: `app/litellm-config.yaml`,
  top-of-file comment — sourced from Alibaba Cloud's own rate-limit and
  pricing console pages, dated 2026-09-03, with caveats about which figures
  are Hong Kong-confirmed vs. inferred.
- **Per-team TPM/RPM values + the 16% rule**: `scripts/mint-team-keys.sh`,
  the `MODEL_TPM_LIMIT`/`MODEL_RPM_LIMIT` comment block immediately above
  where those two JSON maps are defined.
- **Per-team dollar budgets** (a separate, third ceiling — not covered by
  this doc): same script, `TEAM_BUDGET`/`TEAM0_BUDGET` ($100 for team1-5,
  $20 for team0).

## Changing a limit

Edit `MODEL_TPM_LIMIT`/`MODEL_RPM_LIMIT` in `scripts/mint-team-keys.sh`,
update the table in this doc to match, then re-run the script against the
live gateway:

```bash
bash scripts/mint-team-keys.sh https://gateway.hack.gsbn.trade
```

Safe to re-run any time — it's idempotent for key minting (an existing
`TEAMn_VIRTUAL_KEY`/`TEAMn_DSH_VIRTUAL_KEY` in `app/.env` is left alone) but
always re-applies the current rate limits to every team via `/team/update`.
No container restart or redeploy needed — this only calls LiteLLM's API,
it doesn't touch `docker-compose.yml` or anything the
`deepseek-harness-teamN`/`-proxy` sidecar gotcha (see
`docs/deepseek-harness/README.md`) applies to.

To verify what's actually live (rather than trusting the script's static
values), query LiteLLM directly:

```bash
curl -sS -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  "https://gateway.hack.gsbn.trade/team/list" | \
  python3 -c "
import json, sys
for t in json.load(sys.stdin):
    md = t.get('metadata') or {}
    print(t['team_id'], md.get('model_tpm_limit'), md.get('model_rpm_limit'))
"
```

## History

- **2026-09-03**: per-team TPM/RPM limits introduced for the four
  non-qwen models, at an unexplained "~60-65% of an even 5-way split"
  (`deepseek-v4-flash-0731`/`deepseek-v4-pro-0813`: 150,000 TPM / 2,000 RPM;
  `glm-5.2`/`kimi-k2.7-code`: 120,000 TPM / 60 RPM). `qwen3.8-flash` was
  deliberately left uncapped as the fallback target.
- **2026-09-04**: replaced with the current 16%-of-account-ceiling rule for
  both TPM and RPM, applied uniformly to all five models including
  `qwen3.8-flash` (see "Two layers" above for why it's capped now too).
