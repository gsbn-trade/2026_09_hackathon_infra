# bolt.diy: provider lock, real per-model token limits, context-select crash

**Status: implemented and confirmed working (issues 1-2: 2026-08-28, issue
3: 2026-08-30)**, via a custom-built image (`app/Dockerfile.boltdiy` +
`app/patches/`). All three issues below need the same fix mechanism, so they
share one Dockerfile. Confirmed live: a landing-page generation that
previously crashed the container, then chained into multiple "continue"
calls with a missing `package.json`, now completes in one shot; a long-
running chat that previously crash-looped on every follow-up turn once its
context buffer already held what it needed now keeps going. This file is
now a record of *why* it's built this way — useful when upstream changes
something and this needs revisiting, not a live TODO.

## What's actually running now

`docker-compose.yml`'s `boltdiy` service builds `Dockerfile.boltdiy` instead
of pulling `ghcr.io/stackblitz-labs/bolt.diy:latest` directly. That
Dockerfile:

1. Starts from the published image.
2. Copies in three patched source files from `app/patches/`:
   `registry.ts`, `providers/openai-like.ts`, and `.server/llm/select-
   context.ts` (destinations documented inline in the Dockerfile).
3. Installs the dev toolchain (`pnpm install --prod=false`) — the published
   image ships with devDependencies pruned, no `remix` CLI at all.
4. Rebuilds (`pnpm run build`) with a raised Node heap
   (`NODE_OPTIONS=--max-old-space-size=5120`) — **this is the part that
   originally failed** (see below).
5. Prunes devDependencies back out (`pnpm prune --prod --ignore-scripts`;
   `--ignore-scripts` because prune's own `prepare` lifecycle script
   otherwise tries to run `husky`, which prune just removed).

`deploy.sh` now runs `docker compose up -d --build` on the VM instead of
`pull && up -d`, since `boltdiy` no longer has a pullable image.

## Issue 1: provider dropdown showed all ~20 providers, defaulted to Anthropic

Participants shouldn't have to pick a *provider* before picking a *model* —
this deployment only ever configures one real backend (LiteLLM, via the
"OpenAI-Like" custom provider slot), but bolt.diy's stock
`app/lib/modules/llm/registry.ts` registers ~20 providers regardless, and
`LLMManager.getDefaultProvider()` just returns whichever registered first
(`AnthropicProvider`, alphabetically/import-order first). No env var
controls this — confirmed by reading the source, not guessing.

**Fix** (`patches/registry.ts`): export only `OpenAILikeProvider`. Since
`PROVIDER_LIST`, `DEFAULT_PROVIDER`, and the cookie-restore fallback in
`Chat.client.tsx` all derive from whichever providers are registered, this
single change makes OpenAI-Like both the only dropdown entry and the
default — no other code needed changing. Confirmed live: container logs
show only `Registering Provider: OpenAILike`, and `/api/models/OpenAILike`
reports `defaultProvider: OpenAILike`, `total providers: 1`.

## Issue 2: every model showed "8K tokens", output silently chained into multiple slow round-trips

A generation needing more than ~8192 output tokens (e.g. a whole landing
page) didn't fail — it silently chained multiple sequential LLM calls
together ("Continuing message (N switches left)" in the logs), which was
both slow (each link is a full network + generation round-trip) and could
produce **incomplete output** if it ran out of continuation attempts before
finishing everything planned (e.g. `package.json` never written because it
was late in the plan).

Traced to `app/lib/modules/llm/providers/openai-like.ts`'s
`getDynamicModels()`: it fetched `${OPENAI_LIKE_API_BASE_URL}/models` — a
bare OpenAI-style model list (`{id: "..."}`, no token-limit fields) — and
hardcoded `maxTokenAllowed: 8000` for every model regardless of what it can
actually do. That value fed directly into `stream-text.ts`'s
`getCompletionTokenLimit()`, which determines the real `max_tokens` sent
per API call. A separate flat constant,
`app/lib/.server/llm/constants.ts`'s `PROVIDER_COMPLETION_LIMITS.OpenAILike
= 8192`, was the actual fallback in play (also model-agnostic).

**Fix** (`patches/openai-like.ts`): `getDynamicModels()` now tries LiteLLM's
richer `/v1/model/info` first — which reports each model's real
`max_tokens`/`max_output_tokens` (populated explicitly in
`litellm-config.yaml`'s `model_info` blocks for exactly this reason) — and
sets both `maxTokenAllowed` and `maxCompletionTokens` per model from that.
Only falls back to the original `/models`-based 8000-token behavior if
`/model/info` isn't available at all, so the provider still works
generically against any plain OpenAI-compatible backend, not just LiteLLM.
This is more surgical than just raising the flat
`PROVIDER_COMPLETION_LIMITS` constant would have been — that's a single
provider-wide number, and our three models have different real ceilings
(qwen3.7-plus 131072, kimi-k2.7-code 262144, deepseek-v4-flash-0731
~128000); picking one flat value would have either wasted capacity or, for
the lower-ceiling models, caused DashScope to hard-reject requests that
exceeded their real max.

Confirmed live via `/api/models/OpenAILike`: `qwen3.7-plus` →
`maxCompletionTokens: 131072`, `kimi-k2.7-code` → `262144`,
`deepseek-v4-flash-0731` → `128000`. `getCompletionTokenLimit()` prefers
`maxCompletionTokens` when set (`> 0`), so `PROVIDER_COMPLETION_LIMITS` is
no longer reached at all for these models.

## Issue 3: "Custom error: Bolt failed to select files" crash-looped an ongoing chat

Surfaced only after a chat had been running a while (11+ messages, several
files already generated) — every follow-up turn started failing with this
exact error and the preview stopped updating entirely.

Traced to `app/lib/.server/llm/select-context.ts`: when "context
optimization" is on (the default), each turn runs a *separate* LLM call
that's shown the full project file list plus the current context buffer and
asked to return an `<updateContextBuffer>` block naming files to
include/exclude — its own system prompt explicitly says *"If no changes are
needed, you can leave the response empty"*. But the handler code then
computed `totalFiles = ` (newly-included files only) and unconditionally
**threw** `Bolt failed to select files` whenever that count was `0` —
including the fully valid case where the model correctly followed its own
instructions and had nothing new to add because the existing context buffer
already covered the request. Confirmed via container logs: `select-context
Total files: 0` immediately preceded the crash, with no malformed-response
warning anywhere above it — a well-formed, empty response, not a parsing
failure.

**Fix** (`patches/select-context.ts`): when `totalFiles == 0`, return the
existing `contextFiles` (the buffer's current contents) instead of
throwing, so a legitimate "no changes needed" turn just keeps the
conversation going instead of crashing it. The genuine-failure path (no
`<updateContextBuffer>` tag at all, i.e. the model didn't follow the format)
is untouched and still throws `Invalid response. Please follow the response
format`.

## Why this needed a real rebuild (previously deferred)

A plain bind-mount over the source `.ts` files — the trick already used
elsewhere in `docker-compose.yml` for a different bolt.diy fix — does
**not** work here: `dockerstart` (`wrangler pages dev ./build/client`)
serves a bundle **compiled at image-build time**; it never reads `app/`
source at runtime. Confirmed by mounting a patch and checking startup logs,
which still showed all ~20 providers registering.

The build itself (`pnpm run build`, i.e. `remix vite:build`) originally
crashed with `FATAL ERROR: ... JavaScript heap out of memory` under Node's
default V8 heap ceiling — unrelated to how much memory Docker itself had
available. Raising it via `NODE_OPTIONS=--max-old-space-size=5120` on the
build step fixed it outright: build completed in ~38s, no further tuning
needed. That's the one thing that changed between "deferred, too expensive"
and "actually implemented" — the fix was always this Dockerfile, it just
needed the memory ceiling identified and raised first.

Net effect on operations: `docker-compose.yml`'s old runtime `command:` that
installed wrangler and nothing else is gone (wrangler is now baked into the
image), so container start is now *faster*, not slower — all the cost is a
one-time `docker compose build` when `patches/` or the Dockerfile changes,
not a per-start or per-restart tax.
