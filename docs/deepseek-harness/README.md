# DeepSeek Harness: self-hosted deployment (local-only, by design)

**Status: implemented and confirmed working locally 2026-08-31.** Full write-up
of how DeepSeek Harness (`dsh`, `deepseek-ai/deepseek-harness`) is deployed
alongside bolt.diy/Open WebUI/Dify/DeerFlow, why it isn't on a public
subdomain the way the others are, and how the network-namespace-sharing
sidecar it needs actually works. Like the other `docs/*` write-ups, this is
a record of *why*, not a live TODO.

## Why this one is different: dsh refuses to bind non-loopback, on purpose

Every other app in this stack ships a web server meant to sit behind a
reverse proxy. `dsh`'s does not: `dsh web`'s CLI **hardcodes the server to
`127.0.0.1` and exits with a usage error on `--host 0.0.0.0`** — confirmed
directly in the CLI behavior reference, not inferred. This is deliberate:
a `dsh` session gets real bash/filesystem access to its workspace, gated
only by a click-to-approve permission prompt, with no login wall at all
(see [SAFETY.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md)
— "experimental... has not undergone a security audit"; "prefer a
disposable virtual machine, container, or dedicated environment," which is
exactly what running it in its own container already gives it). Putting
that on a public subdomain the way DeerFlow got one would mean anyone with
the URL gets agent-mediated shell access to that container — a materially
different risk than Dify (per-workspace accounts) or DeerFlow (its own
admin-account first-run flow) or bolt.diy (sandboxed WebContainer, no real
host access). **Decision: local-only for now** — reachable via
`http://localhost:3080` on whatever machine runs the stack, or an SSH
tunnel to the VM, never a Caddy route. Revisit (with Basic Auth in front, at
minimum) before ever giving participants a URL.

## How it's reachable at all, given that constraint

Docker's own port publishing can't help here either: a process bound to
`127.0.0.1` *inside* a container only accepts connections that already
originate from that container's own network namespace — a host-side
`-p 3080:3080` does not reach it, because packets arrive via the container's
bridge interface, not its loopback. So even "local-only" needs something
sharing dsh's network namespace to bridge the two loopbacks.

`docker-compose.yml`'s `deepseek-harness-proxy` is that something: a
`caddy:2-alpine` sidecar with `network_mode: "service:deepseek-harness"` —
Compose's way of saying "don't get your own network identity, join this
other service's namespace instead." Inside that shared namespace, Caddy
listens on every interface (`:3080` in `deepseek-harness/Caddyfile`, no
scheme = HTTP-only, no auth) and reverse-proxies to `127.0.0.1:3080` — which
*is* dsh's own loopback now, since they share a namespace. `dsh` itself
never has to bind anything but its own safe default.

One Compose wrinkle this depends on: **`ports:` must be declared on the
namespace *owner*, not the joiner.** `deepseek-harness` created the
namespace, so `docker-compose.override.yml`'s `127.0.0.1:3080:3080`
publish lives on that service, even though nothing in that container is
actually listening — Caddy, in the *other* container, is what answers,
because sockets are per-namespace, not per-container. Confirmed by reading
back `docker compose config`'s resolved output before trusting it, not just
by the compose file parsing without error.

The published port is loopback-only (`127.0.0.1:3080`, not `3080:3080`) and
lives only in `docker-compose.override.yml` — excluded from the VM by
`deploy.sh`'s rsync, same as every other local-dev-only override in that
file. On the VM, reach it with an SSH tunnel
(`ssh -L 3080:localhost:3080 root@<vm-ip>`) if this override is copied over
by hand; there's no default cloud-reachable path, on purpose.

**Operational consequence, learned the hard way (2026-09-03):** since the
`-proxy` sidecar only resolves "which namespace do I join" at its own
container-*creation* time, restarting or recreating a `deepseek-harness-
teamN` container alone leaves that team's `-proxy` sidecar attached to the
old, now-gone namespace — nothing is listening on the shared loopback port
anymore, and Caddy's front door 502s that team's whole subdomain until the
sidecar is recreated too. This took down all six teams' public URLs for
about 30 minutes before it was caught (a config-only `docker compose
restart` on the six main containers, proxies never touched). A plain
`restart` on the proxy doesn't fix it either — it must be recreated (`up -d
--force-recreate`) *after* its main container is up. Always use
`scripts/restart-dsh-team.sh <N>` (or `all`) for any restart/recreate of a
team's harness — it does both together and curls the URL afterward to
confirm — rather than hand-typing `docker compose restart` against a single
service. See the `CAUTION` comment on each `-proxy` block in
`docker-compose.yml` for the same warning at the point of edit.

## Deployment approach: npm install, not a source vendor

Unlike DeerFlow, `dsh` ships as a normal published npm release
(`@deepseek-ai/dsh`) — no from-source build, no sparse-checkout vendor.
`app/deepseek-harness/Dockerfile` is `node:22-slim` +
`npm install -g @deepseek-ai/dsh@0.1.1-rc.2`, pinned to an exact version
rather than floating `@latest` — the project's own README: "developer
preview... THERE WILL BE COMPATIBILITY-BREAKING CHANGES."

## Model provider: LiteLLM via the generic OpenAI-completions route

Same LiteLLM instance as every other app, different virtual key
(`DEEPSEEK_HARNESS_VIRTUAL_KEY` in `app/.env`, same mint-via-`/key/generate`
pattern as `TEAM_VIRTUAL_KEY`). Wired through `dsh`'s own
`llm-pi-ai` plugin — the adapter for "a gateway pi-ai's installed catalog
doesn't describe" — in `app/deepseek-harness/home/settings.yaml`:

```yaml
llm-pi-ai:
  providers:
    litellm:
      displayName: Hackathon LiteLLM
      apiKeyEnv: DEEPSEEK_HARNESS_VIRTUAL_KEY
      api: openai-completions
      baseURL: http://litellm:4000/v1
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: qwen3.8-flash
        - id: deepseek-v4-flash-0731
        - id: deepseek-v4-pro-0813
        - id: glm-5.2
```

`kimi-k2.7-code` deliberately isn't in this list (2026-09-01): it's the
strongest of the roster for coding, which is bolt.diy's job — the other
four already cover what DeepSeek Harness needs, no reason to offer it here
too. It stays wired in `litellm-config.yaml` for bolt.diy.

`apiKeyEnv` is a credential *reference* (an env var name), not a literal
secret in the file — same shape as `os.environ/DASHSCOPE_API_KEY` in
`litellm-config.yaml`. `compat` is set proactively, not reactively: dsh's
own docs call out that a custom OpenAI-compatible gateway usually fails on
two things a reasoning model triggers — the system prompt sent as
`role: "developer"`, and the output cap sent as `max_completion_tokens` —
both of which Alibaba Cloud Bailian (what LiteLLM actually proxies to
here — the only LLM provider in this stack; Kimi is Bailian-hosted too, no
separate Moonshot account) don't understand. Set once on the route rather
than discovered per-model the hard way.

`settings.yaml` is real, gitignored data, not an upstream-shipped example
(unlike DeerFlow's `config.example.yaml`) — the app itself may rewrite parts
of it at runtime (e.g. recording a picked default model), so it's seeded by
hand here and documented rather than tracked. See `app/.gitignore`.

## Multi-agent teams: Tier 1 (shipped) vs. Tier 2 (attempted, blocked)

dsh has two distinct delegation systems, and only one of them is actually
running here:

- **Tier 1 — stable, what's deployed.** `tool-subagent`/`tool-subagent-fork`
  (spawn a named child), `tool-subagent-control`
  (`send_message`/`interrupt_agent`/`list_agents` while it runs), and
  `tool-subagent-report` (the child reports back). Hub-and-spoke: children
  talk to the Lead, not to each other.
- **Tier 2 — experimental, real peer-to-peer.** `packages/experimental/
  agent-team` + `tool-agent-team`: ten model tools (`spawn_teammate`,
  `send_message`, `followup_task`, `list_agents`, `wait_agent`,
  `interrupt_agent`, `team_task_create/list/get/update`) where *any*
  teammate can message *any other* teammate and read/claim work off one
  shared task board — plus a live roster + task-board panel in the browser.
  This is the closer match to "multiple agents communicate with each other
  and reach consensus." **Confirmed by reading the actual package source**:
  explicitly excluded from the published npm release ("available only from
  a source checkout" — both package READMEs say this outright), so it
  cannot be reached from the npm-installed deployment above at all.

### What was tried

A second Dockerfile built dsh from source instead (`git clone` +
`corepack use pnpm` + `pnpm install` + `pnpm run build`, ~230s, 3GB image)
and an `entrypoint.sh` that ran `dsh plugin --profile web add
./packages/experimental/agent-team-profile` and `...-web-profile` before
booting — the exact sequence both package READMEs document, read from
`apps/cli/src/plugin.ts`'s actual source (not inferred from prose): it
auto-initializes the profile if needed, anchors the relative plugin path
against the *invoking* directory (not the profile directory pnpm actually
runs in), and after a successful `pnpm add` inspects the new dependency for
a `dsh.bundle.patch` export and appends it to `dsh.profile.bundles`
automatically — the same mechanism `dsh-base`/`dsh-web-app` are composed
by. Two real bugs surfaced and got fixed along the way: `node --import
tsx/esm` resolves bare specifiers against the process's CWD, not the entry
script's location, so running with CWD=`/workspace` (correct, for dsh's own
"invoking directory is the workspace root" rule) couldn't find `tsx` itself
— fixed with a runtime symlink, `/workspace/node_modules →
/opt/dsh-src/node_modules`, created by the entrypoint (a Dockerfile-time
symlink would be shadowed by the `/workspace` bind mount).

### Where it's actually blocked

`apps/cli/src/profile-boot.ts` failed with `SyntaxError: The requested
module '@deepseek-ai/cordis' does not provide an export named
'FiberState'`. Traced to `vendor/cordis/src/fiber.ts:147`:
`export const enum FiberState`. A TypeScript `const enum` is fully erased
at compile time by design — every usage gets inlined as a literal, and no
runtime export exists for it, which is exactly what `vendor/cordis/lib/
index.js`'s real export list confirmed (`Fiber` is there; `FiberState`
genuinely is not — checked the built file directly, not just the error
message). `tsx`/esbuild transpile each file independently, without
cross-file type information, so they can't tell the erasure was
*intentional* and treat the import as a plain missing export. This is an
incompatibility between how this repo's own `pnpm dsh` dev command
apparently resolves workspace packages in the maintainers' own environment
and how a plain `git clone` → `pnpm install` → `tsx` resolves them outside
it — not a Docker or config problem on this side.

**Decision: reverted to Tier 1** (the npm-installed Dockerfile, confirmed
working — see Verification below) rather than keep chasing an explicitly
"experimental... no stability promise" feature. If this gets revisited:
worth checking whether a *built* CLI invocation (`pnpm run build` then the
compiled `apps/cli/lib/bin.js`, not `tsx` source-execution) sidesteps the
`const enum` issue, since a real `tsc`/tsdown build — as opposed to tsx's
per-file transpile — has full cross-file type information and would erase
the enum consistently on both sides instead of only one.

## Track presets: one per hackathon track

Four presets live under `app/deepseek-harness/home/.agent-presets/` — hand-
authored directly (same "pre-seed the file" approach as `settings.yaml`,
not created through the UI's copy-flow), each a copy of the shipped
`standard` preset's full tool composition (bash, fs, web, skills, goal,
plan mode, Tier 1 delegation, ask-user, todo) with one changed row: the
`persona`. Every persona shares three non-negotiable instructions, straight
from what actually matters about this data:

1. **The sample data is synthetic — say so.** Every persona explicitly
   frames findings from `/workspace/data` as "the kind of issue this data
   shape would surface," never as a real-world fact. The data is a
   plausible shape to demo against, not evidence.
2. **Real web research and the user's real answers are the authoritative
   parts.** Every persona is told to ground terminology/standards claims in
   actual industry references (SMDG, UN-CEFACT, etc.) via `tool-web`, and
   to use `ask_user_question` rather than guess at business intent — those
   two things are real, unlike the CSV numbers.
3. **Form a team when the problem actually has independent angles**, not
   as theater — and only write a final answer once the angles agree or the
   disagreement is explained.

| Preset directory | Track | Team shape |
|---|---|---|
| `track4-transshipment-team` | 4 — Transshipment Visibility | **Built as the proof of concept.** Mainliner-view + terminal-view agents reconcile disagreeing schedule data — mirrors the track's own real premise (three stakeholders who don't see the same schedule). |
| `track2-move-reconciliation-team` | 2 — Terminal Ops (TDR) | Operator-view + crane-view agents independently compute the same move totals — a *checkable* consensus (the totals must literally match), not just a narrative one. |
| `track1-schedule-recovery-team` | 1 — Vessel Schedule | Voyage/timing-risk + capacity/commercial-risk agents — two angles that don't reduce to one number, reconciled into a recovery recommendation. |
| `track3-edi-validator` | 3 — EDI/Data Exchange | Deliberately **not** a debate team — the brief itself says pick one lane (validator / Excel converter / JSON translator) and build it well; a team here only splits genuinely separable build labor, doesn't argue toward consensus. |

Every preset composes on **Tier 1** delegation (see above) — "spawn
teammates... message them" in the persona text runs on the stable
hub-and-spoke tools, not true peer messaging. If Tier 2 ever gets unblocked,
revisit the wording (each file's header comment flags this).

Structural validation only so far: all four `preset.yml`/`agent.cordis.yml`
pairs parse as valid YAML with the expected 17-row composition, and the app
boots and serves `200` with all four present — no crash, no "broken preset"
signal in the logs. Traced the actual wire protocol trying to verify
further without a browser (`POST /api/<namespace>/<method>` with a typed
`{type, rpcId, method, payload}` JSON envelope — see
`packages/client/dsh-api-gateway` and `dsh-client-connection`'s
`callUnary()`), and found the roster method itself
(`AgentPresets.remoteExportList`, `@Remote('list')` in
`packages/preset/agent-presets/src/index.ts`), but couldn't pin down the
exact namespace string blind (`agent-presets`, `agentPresets`, `presets`,
`agent-preset` all `404`d) without either the compiled server route table
or a live session context. **Not verified**: an actual session picking
each preset from the UI — needs a browser, which isn't available in this
environment. See [participant-guide.md](participant-guide.md) for the
per-track instructions and example prompts to use for that check.

## Web search needs a second, different credential

Every preset's persona instructs it to ground claims in real web research —
but `tool-web` being enabled in a preset is necessary, not sufficient. Found
live, from a real "no usable web provider is registered" error a session
hit: the actual search work is done by a separate provider plugin mounted
at the *profile* level (`dsh --dump-config` confirms it:
`@deepseek-ai/dsh-web-search-deepseek`, `searchProvider: deepseek-official`
on the `dsh-web` service) — `tool-web` is just the model-facing front door
to whatever provider is registered there.

Read that provider's own README directly rather than guessing: it does
**not** proxy through the normal chat model or LiteLLM at all. It makes its
own call to `https://api.deepseek.com/anthropic/v1/messages` — DeepSeek's
Anthropic-compatible API, using DeepSeek's *native server-side*
`web_search_20250305` tool; DeepSeek's own servers perform the search.
It needs `DEEPSEEK_API_KEY`, a real DeepSeek **platform** key from
`platform.deepseek.com` — a completely different credential from
`DEEPSEEK_HARNESS_VIRTUAL_KEY` (a LiteLLM virtual key, routed to Bailian,
which this provider never touches). Nothing in this deployment had ever
set `DEEPSEEK_API_KEY`, so the provider had no credential and refused to
register — a clean, correctly-reported failure, not a bug in any preset.

**The other real option**, checked against npm rather than assumed:
`dsh-web-search-exa` and `dsh-web-search-perplexity` both exist as
alternative providers. Not used here — both are non-Chinese vendors
needing their own new account, which cuts against this whole project's
Chinese-models-only posture, and DeepSeek is already one of the four
approved model families, so a DeepSeek platform key is the natural fit.

**Status: confirmed working 2026-09-01.** `DEEPSEEK_API_KEY` is threaded
through `docker-compose.yml` → `app/.env`/`.env.example`, same
blank-until-filled pattern as every other credential in this repo.

Two real gotchas hit while confirming it, worth recording:

- **Recreating `deepseek-harness` alone breaks the proxy sidecar.**
  `deepseek-harness-proxy` uses `network_mode: "service:deepseek-harness"`,
  which ties it to that specific container instance, not just the service
  name — `docker compose up -d --force-recreate deepseek-harness` alone
  left the proxy running against the now-gone old container (`curl
  localhost:3080` → connection failure, not even a clean HTTP error).
  `docker compose up -d --force-recreate deepseek-harness-proxy`
  afterward fixed it. Recreate both together going forward.
- **A valid key with zero balance fails with `402 Insufficient Balance`,
  not a `401`** — confirmed by testing the raw API directly (`node`'s
  built-in `fetch` from inside the container; the image has no `curl`).
  This applies to *any* DeepSeek API call on that key, not just
  `web_search` — worth checking first if this ever recurs, since it looks
  identical to a wiring problem from the dsh-side error alone. Also: the
  widely-repeated "5M free tokens, no card required" claim from
  third-party pricing aggregators did **not** hold for this account — both
  the Anthropic-compatible and plain chat-completions endpoints returned
  `402` until the account was topped up with real balance. Don't repeat
  that claim as fact; it wasn't sourced from DeepSeek's own docs and
  didn't match what a real key showed.

After a top-up, the same direct test against
`https://api.deepseek.com/anthropic/v1/messages` with the
`web_search_20250305` tool returned a real `200` and a genuinely relevant
result (the actual SMDG BAPLIE user manual PDF, not a hallucinated hit) —
confirming the key, the endpoint, and the tool wiring all work end to end.

## Workspace and persistence

- `app/deepseek-harness/home/` → `$DSH_HOME` (`/data/.dsh`) — settings,
  credentials, session/profile state. Bind-mounted so it survives container
  recreation, same reasoning as every other app's persistent volume in this
  stack.
- `app/deepseek-harness/workspace/` → `/workspace`, the agent's read-write
  working directory (`WORKDIR` in the Dockerfile) — where it actually reads
  and edits files, runs commands.
- `../data` (the hackathon track data) → `/workspace/data`, **read-only** —
  same "every team gets every track, read-only, no upload needed" pattern
  as Open WebUI's Jupyter mount, for the same reason (track assignment
  isn't known ahead of time).

Both `home/` and `workspace/` are gitignored in full (`app/.gitignore`) —
real credentials/session state in the former, arbitrary agent-generated
files in the latter.

## Telemetry: disabled outright

Upstream defaults to feedback-gated telemetry (nothing uploaded until a
user explicitly runs `/feedback`, at which point the *whole* session
uploads — message text, tool arguments and results, workspace paths, no
redaction). Set `DSH_TELEMETRY_MODE=DISABLED` in the Dockerfile rather than
relying on nobody hitting `/feedback` — matches this repo's general
carefulness about what leaves the VM (see the DashScope/SSRF-proxy notes
elsewhere in `docs/`).

## Known quirks (found while wiring this up)

- **A brand-new team instance shows "no workspace configured" and no
  presets, and clicking "Select Workspace Directory" fails with
  `transport failure for /api/host.listDirectory: HTTP 403`.** Confirmed
  live (2026-09-02, first real participant-facing use of `team0` after
  going always-on) — not a bug in this deployment, a deliberate upstream
  restriction. Grepped the installed package's own docs
  (`dsh-host-apiproxy`'s README, `node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-host-apiproxy/`):
  `host.listDirectory`/`host.pickDirectory` (the directory *browser*) and
  the whole `settings.*`/`credentials.*` configuration plane are
  explicitly restricted to loopback, same-origin requests — "the browser
  carrier applies the same loopback, same-origin restriction... covers
  all of these like every other `/api` request." Since every team's
  instance is reachable only through Caddy on a public subdomain, that
  check can never pass, for any team, regardless of Basic Auth,
  `X-Forwarded-*` headers, or anything else adjustable from this side —
  it isn't checking auth, it's checking that the request never left the
  host at all.
  
  The fix isn't in the restricted `host.*` browse API at all: registering
  an *already-known* path is a separate, unrestricted RPC,
  `workspace.create` (see `@deepseek-ai/dsh-workspace`'s README — takes a
  literal path, no directory listing involved, so the loopback rule
  doesn't apply to it). Called directly against each container's own
  `127.0.0.1:3080` (via `docker exec` + Node's built-in `fetch`, which
  is itself loopback regardless — belt and suspenders even though the
  method isn't gated), using the wire format documented in
  `dsh-host-apiproxy`'s own `rpc.d.ts`:
  ```js
  fetch("http://127.0.0.1:3080/api/workspace.create", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      type: "client-request", rpcId: "seed-workspace-team0",
      method: "workspace.create", payload: {path: "/workspace"}
    }),
  })
  ```
  Idempotent — a second call for a path already owned by a workspace
  returns the existing one (`created: false`) instead of erroring, so
  it's safe to run against every team unconditionally. Once a workspace
  exists, the "no presets" symptom resolves on its own — the preset
  picker was never broken, it just had nothing to attach a session to.
  Automated in `scripts/seed-dsh-workspaces.sh` — run once after any
  fresh deploy, or after resetting a team's `home-teamN/` state.

- **The proxy sidecar can't listen on the same port dsh already owns in
  their shared namespace.** First attempt had `deepseek-harness-proxy`
  listen on `:3080` too (matching the externally-visible port, seemed
  natural) — `dsh` immediately failed to boot with
  `listen EADDRINUSE: address already in use 127.0.0.1:3080`, since it was
  racing the sidecar for the exact port both processes see as available in
  their one shared namespace. Fixed by having the proxy listen on `:8080`
  internally instead and mapping the *host* publish
  (`docker-compose.override.yml`) as `127.0.0.1:3080:8080` — externally
  still `localhost:3080`, internally two different ports so they stop
  colliding.

## Verification

Confirmed locally: image built clean (`node:22-slim` + a single
`npm install -g`, no from-source build — much lighter than DeerFlow's);
both containers came up with no errors in either log; `curl
http://localhost:3080/` returned `200` with the real app shell (through the
Caddy sidecar, proving the network-namespace-sharing trick actually works);
`/data/.dsh/settings.yaml` came back exactly as written, with no parse-error
crash-loop, and dsh had otherwise initialized its own profile directory
around it undisturbed; and, from inside the `deepseek-harness` container
itself, a direct `POST /v1/chat/completions` to `litellm:4000` using
`$DEEPSEEK_HARNESS_VIRTUAL_KEY` got a genuine `qwen3.7-plus` response back —
confirming the exact network path and credential dsh's own `llm-pi-ai`
route will use.

**Not verified**: an actual agent session driven through dsh's own UI/RPC
protocol (it isn't a simple REST API — `/api/models` and similar guesses
all `404`; the client boots a custom typed RPC gateway over its own
transport) — that needs a browser, not `curl`. Open `http://localhost:3080`
(or tunnel to it on the VM) and pick the `litellm` provider from Settings →
Models to confirm the route resolves inside the app itself.
