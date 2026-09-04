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

`kimi-k2.7-code` is the one exception to the 16% rule — see "Why
kimi-k2.7-code's TPM cap isn't 16%" below.

## Quota table

| Model | Account TPM | Team TPM | Account RPM | Team RPM (16%) |
|---|---:|---:|---:|---:|
| `qwen3.8-flash` | 2,500,000 | 400,000 (16%) | 15,000 | 2,400 |
| `deepseek-v4-flash-0731` | 1,200,000 | 192,000 (16%) | 15,000 | 2,400 |
| `deepseek-v4-pro-0813` | 1,200,000 | 192,000 (16%) | 15,000 | 2,400 |
| `glm-5.2` | 1,000,000 | 160,000 (16%) | 500 | 80 |
| `kimi-k2.7-code` | 1,000,000 | 350,000 (exception) | 500 | 80 |

Same per-team caps apply identically to every team, team0 through team5 —
there's no per-team variation today. `kimi-k2.7-code` is bolt.diy-only
(deliberately excluded from DeepSeek Harness's own model list — see
`app/deepseek-harness/home/settings.yaml`'s comment) but the team-level cap
above still applies to it, since bolt.diy and dsh share one `team_id`.

### Why kimi-k2.7-code's TPM cap isn't 16%

Confirmed live 2026-09-04 (build0, bolt.diy team0): at 160,000 (the 16%
figure), **every single** kimi-k2.7-code call from any team failed, 100% of
the time — not intermittently under load. Symptom: team0 showed *zero*
kimi-k2.7-code usage in the LiteLLM dashboard despite repeated real
attempts.

Root cause is in LiteLLM's own rate limiter
(`parallel_request_limiter_v3.py`), not DashScope: it reserves
`input_tokens + max_tokens` *upfront*, before the request is ever sent to
the provider, and rejects immediately if that projected total exceeds the
remaining per-key TPM budget — which is why the failed calls never showed
up as real usage; they never went out. bolt.diy always requests each
model's own real ceiling as `max_tokens` (see `docs/bolt-provider-lock`'s
issue 2 — this is deliberate, avoiding the truncated multi-round-trip
generations that fix was written for), so every kimi-k2.7-code call carries
`max_tokens=262144`. That alone already exceeds 160,000, so no call could
ever clear the reservation check regardless of actual usage or timing.

350,000 clears the 262,144 floor with room for input/prompt tokens too.
Trade-off: two teams bursting kimi-k2.7-code in the same 60-second window
can now approach the shared 1,000,000 account ceiling (700,000 of it) —
beyond that, DashScope's own real "Allocated quota exceeded" applies. That
part is a genuine scarcity of this model's account quota (only bolt.diy
uses kimi-k2.7-code, and its max_tokens is a full 2x qwen3.8-flash's own
ceiling), not something any per-team number can fix.

### The floor: a per-team TPM cap must clear what the client actually requests

Generalizing the kimi-k2.7-code lesson above, since it applies to any model
added to this config later, not just kimi-k2.7-code specifically: because
LiteLLM's TPM limiter reserves `input_tokens + max_tokens` *upfront* (see
above), **a per-team TPM cap that's lower than the `max_tokens` value the
client actually sends on a call is not a tight-but-workable limit — it's a
100%-failure-rate outage for that model**, indistinguishable from "the
model is down" to whoever's using it, and (as seen here) invisible in the
LiteLLM dashboard's usage numbers since the request never goes out.

Before setting or changing any per-team TPM cap, know what `max_tokens`
each real client actually sends for that model — not just the model's
provider-confirmed ceiling (`app/litellm-config.yaml`'s `model_info.
max_tokens`). For bolt.diy that's the same number (it always requests the
full ceiling — `docs/bolt-provider-lock`'s issue 2), which is why the 16%
rule breaks specifically on kimi-k2.7-code, the one model whose ceiling
(262,144) is larger than 16% of its own account-wide TPM ceiling
(160,000). It's the *ratio* of a model's max_tokens to its own account-wide
TPM ceiling that determines whether the 16% rule is safe for it — worth
rechecking this ratio for any newly-added model rather than assuming 16%
just works.

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
