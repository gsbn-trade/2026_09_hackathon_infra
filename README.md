# Shanghai hackathon — LiteLLM + bolt.diy on AliCloud

See [ARCHITECTURE.md](ARCHITECTURE.md) for the target system, diagrams, and
what's built vs. still planned — this file is the hands-on deploy guide.

One VM, provisioned with OpenTofu; one Docker Compose stack on top (Caddy →
LiteLLM + bolt.diy, Postgres backing LiteLLM). The same `app/` directory
also runs unmodified on the Mac Mini backup — that's the point.

Layer split, and why: **OpenTofu owns the AliCloud resources** (VM,
network, security group, EIP) so the whole environment is destroyable and
re-creatable from a diff, not remembered console clicks. **Docker Compose
owns everything that runs on the VM** — faster to iterate on, and testable
locally (see below) without touching AliCloud at all. Kubernetes/ACK would
be overkill for two containers on one box; a hand-rolled bash script would
lose the easy `tofu destroy` after the event.

OpenTofu, not Terraform, by request — it's the Linux Foundation-governed,
MPL-licensed open-source fork. Same HCL, same AliCloud provider, same state
format; only the CLI binary name (`tofu` instead of `terraform`) and one
explicit provider-registry pin differ. Everything in `infra/` would work
unmodified with `terraform` too, if that ever changes.

## What you need before starting

- An AliCloud account with an **AccessKey ID/Secret** for a RAM user scoped
  to ECS/VPC/EIP (not your root account key).
- The Alibaba Cloud CLI (`aliyun`), used once to store that AccessKey
  locally so it never has to be typed into a shell command or a chat.
  On macOS, per the [official install guide](https://www.alibabacloud.com/help/en/cli/install-update-alibaba-cloud-cli#h2-install-macos-en-001):

  ```bash
  brew install aliyun-cli
  ```

  or, without Homebrew:

  ```bash
  curl https://aliyuncli.alicdn.com/aliyun-cli-macosx-latest-universal.tgz -o aliyun-cli-macosx-latest-universal.tgz
  tar xzvf aliyun-cli-macosx-latest-universal.tgz
  sudo mv ./aliyun /usr/local/bin
  ```

  Verify with `aliyun version`.
- OpenTofu installed locally: `brew install opentofu` (installs the `tofu`
  command)
- A domain (or subdomain) you can point DNS at — **required**, not optional:
  bolt.diy's in-browser sandbox (WebContainers) needs a real HTTPS secure
  context to run at all, so a bare IP over `http://` will not work for the
  build track. Caddy handles the certificate automatically once DNS points
  at the VM.
- A Bailian (Model Studio) API key — covers Qwen + DeepSeek + GLM + Kimi.
  This is the only LLM provider; no separate Moonshot platform account is
  used (Bailian hosts Kimi itself).
- A real DeepSeek platform API key (`platform.deepseek.com`) — separate
  from the Bailian key above, used only by DeepSeek Harness's web-search
  tool (calls DeepSeek's own API directly, not through Bailian/LiteLLM).
  See [docs/deepseek-harness/](docs/deepseek-harness/). Optional: the app
  runs fine without it, just with web search disabled.

### Configuration steps log
1. Created a [RAM user](https://ram.console.alibabacloud.com/users) and Users > [User] > Permissions: `AliyunRAMFullAccess` and `AliyunSTSAssumeRoleAccess`.
2. Following [Oauth credentials](https://www.alibabacloud.com/help/en/cli/oauth-credentials?spm=a2c63.p38356.help-menu-29991.d_1_0_0.1886d384ZFYCWJ), run
```
aliyun configure --mode OAuth --profile OAuthProfile

OAuth Site Type (CN: 0 or INTL: 1, default: CN): 
1
Please open the following URL in your browser to authorize:
<link redacted>
If the browser does not open automatically, use the following URL to complete the login process:

SignIn url: <link redacted>

Now you can login to your account with OAuth configuration in the browser.
OAuth configuration completed. The temporary Access Key Id and Access Key Secret have been set in the profile.
Default Region Id []: cn-hongkong
Default Output Format [json]: json (Only support json)
Default Language [zh|en] en: en
Saving profile[OAuthProfile] ...Done.
```
3. For this to work, needed to open [Integrations > OAuth (Preview) > "official-cli"](https://ram.console.alibabacloud.com/applications/4103531455503354461?appType=ThirdPartyApp) 3P application and add created RAM user to [Allowed Identities](https://ram.console.alibabacloud.com/applications/4103531455503354461?appType=ThirdPartyApp&activeTab=Assignments).

```
# Set Role based access
aliyun configure set --ram-role-arn acs:ram::5489273919625675:role/smdg-hackathon-sts-role

# Verify identity
aliyun sts get-caller-identity
```

NOTE: it was difficult to figure out how to assume role with oatuh or sts login. Instead, created AccessId/Secrte for a user and assigned them `AliyunECSFullAccess` and `AliyunVPCFullAccess` roles.

```
# Set region to Hong Kong to avoid ICP license filing
aliyun configure set --profile default --region cn-hongkong
aliyun configure list
Profile   | Credential         | Valid   | Region           | Language
--------- | ------------------ | ------- | ---------------- | --------
default * | AK:***uVB          | Valid   | cn-hongkong      | en
```

## 1. Provision the VM

First, store your AccessKey once via the CLI instead of exporting it raw —
`aliyun configure` prompts interactively (AccessKey ID, AccessKey Secret,
region `cn-hongkong`, default output format), and writes it to
`~/.aliyun/config.json`:

```bash
aliyun configure
# → writes a profile named "default" unless you pass --profile <name>
```

If you're scripting this non-interactively instead (CI, no TTY):

```bash
aliyun configure set --profile default --mode AK \
  --access-key-id "..." --access-key-secret "..." --region cn-hongkong
```

The alicloud provider does **not** pick up `~/.aliyun/config.json`
automatically just because it exists — it needs to be told which profile to
use. `versions.tf` sets `profile = "default"` in the `provider "alicloud"`
block to match what `aliyun configure` writes by default. If you used a
different profile name, override it without editing code:

```bash
export ALIBABA_CLOUD_PROFILE="<your-profile-name>"
```

(The raw env-var route still works too, if you'd rather not touch the CLI
config at all — it just leaves the secret sitting in shell history. Note the
current provider version expects the newer variable names, not the legacy
`ALICLOUD_*` ones:)

```bash
export ALIBABA_CLOUD_ACCESS_KEY_ID="..."
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="..."
export ALIBABA_CLOUD_REGION="cn-hongkong"
```

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_cidr to your IP (https://ifconfig.me),
# confirm ssh_public_key_path points at a real key you hold

tofu init
tofu apply
```

(`terraform.tfvars` is the right filename here, not `tofu.tfvars` — OpenTofu
kept Terraform's file-naming conventions for drop-in compatibility.)

Note the `public_ip` in the output. Point two DNS A records at it:
`gateway.<your-domain>` and `build.<your-domain>`.

## 2. Configure the app

```bash
cd ../app
cp .env.example .env
# fill in POSTGRES_PASSWORD, LITELLM_MASTER_KEY, LITELLM_SALT_KEY
# (openssl rand -hex 32 for the last two), DASHSCOPE_API_KEY
# set COMPOSE_PROFILES=cloud (turns Caddy on — see Testing locally below
# for why it's off by default); leave TEAM_VIRTUAL_KEY blank for now
```

Edit `Caddyfile`: replace `gateway.example.com` / `build.example.com` with
your real subdomains.

For getting/validating the DASHSCOPE_API_KEY specifically —
issuing a Model Studio key, picking the right regional endpoint, debugging
a rejected key — see [docs/alicloud-api-key/](docs/alicloud-api-key/), which
has ready-to-run scripts for the whole cycle (`create-key.sh`,
`smoke-test-provider.sh`, etc.), not just narrative docs.

## 3. First deploy

```bash
cd ..
./deploy.sh
```

This copies `app/` to the VM and runs `docker compose up -d`. LiteLLM and
Caddy will come up; bolt.diy will come up too but its model calls will
401 until step 5, because `TEAM_VIRTUAL_KEY` is still blank.

## 4. Confirm LiteLLM is alive and can reach the models

```bash
curl https://gateway.<your-domain>/health/liveliness

curl https://gateway.<your-domain>/v1/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3.8-flash", "messages": [{"role":"user","content":"ping"}]}'
```

If a model 404s, its id likely shifted on Bailian's side — check the Model
Square in the Bailian console and fix the string in `app/litellm-config.yaml`,
then `./deploy.sh` again.

## 5. Mint a team virtual key

For the full 5-team setup, `scripts/mint-team-keys.sh` does this 12 times
over (see "Scaling to 5 teams" below) — the manual version here is worth
knowing for a single test key, or for debugging what that script does
under the hood:

```bash
curl https://gateway.<your-domain>/key/generate \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
        "team_id": "team-1",
        "max_budget": 20,
        "models": ["qwen3.8-flash", "deepseek-v4-flash-0731", "deepseek-v4-pro-0813", "kimi-k2.7-code", "glm-5.2"]
      }'
```

(Create the team first with `POST /team/new` if you want team-level budget
aggregation across multiple keys — for a single test key this step alone is
enough.) Take the returned `key` value, put it in `app/.env` as
`TEAM1_VIRTUAL_KEY`, then:

```bash
./deploy.sh
```

## 6. Use it

Every team-facing URL below is gated by HTTP Basic Auth — see "Scaling to
5 teams" for how credentials get generated.

- `https://build1.<your-domain>` .. `build5.<your-domain>` —
  bolt.diy, one instance per team. OpenAI-Like is the only provider and is
  pre-selected (patched, see Known quirks below); the model dropdown should
  show `qwen3.8-flash` / `deepseek-v4-flash-0731` / `deepseek-v4-pro-0813`
  / `kimi-k2.7-code` / `glm-5.2`.
- `https://team1.<your-domain>` .. `team5.<your-domain>` —
  DeepSeek Harness, one instance per team, four hand-authored per-track
  presets to pick from (see
  [docs/deepseek-harness/](docs/deepseek-harness/)).
- `https://analyze.<your-domain>` — Open WebUI, **kept as a backup, not a
  primary track tool** (see [ARCHITECTURE.md](ARCHITECTURE.md#evaluated-not-used)):
  chat + a real Python/pandas code interpreter (Jupyter backend) with every
  `data/` track mounted read-only at `~/data` — no upload needed,
  `pd.read_csv('data/Track 1 - Vessel Schedule/bookings.csv')` just works.
  The app itself has no login wall (`WEBUI_AUTH=False`, same "just open the
  URL" pattern as bolt.diy), but Caddy gates it with one shared Basic Auth
  passphrase (username `guest`) — see "Scaling to 5 teams".
- `https://gateway.<your-domain>/ui` — LiteLLM's admin dashboard: spend,
  teams, keys, logs.
- `build0.<your-domain>` / `team0.<your-domain>` — **organizer
  testing only**, same apps as above but not started by a plain
  `docker compose up -d` (see "Scaling to 5 teams" for how to start them on
  demand) — 502s until you do.

Open WebUI needs its own `OPENWEBUI_VIRTUAL_KEY` minted the same way as
step 5's team keys (separate key so its spend/budget tracks
independently), plus `OPENWEBUI_SECRET_KEY` and `JUPYTER_TOKEN`
(`openssl rand -hex 32` / `-hex 24`) in `app/.env` — see `.env.example`.
Needs its own DNS A record for `analyze.<your-domain>` too, same as
`gateway`/`buildN`.

## Testing the stack locally first (no AliCloud needed)

Since this is just Docker Compose, you can sanity-check it on your own
machine before ever touching AliCloud — useful for catching config typos
cheaply, and it's the same rehearsal the Mac Mini backup plan relies on.
This is also the recommended way to iterate day-to-day — cheaper and much
faster than redeploying to the VM for every change.

```bash
cd app
cp .env.example .env   # fill in real provider keys if you want live calls;
                        # containers still boot fine without them.
                        # Leave COMPOSE_PROFILES blank (the default) — this
                        # skips Caddy entirely.
docker compose up -d
curl http://localhost:4000/health/liveliness   # LiteLLM
open http://localhost:5173                     # bolt.diy
```

No TLS setup needed locally: `docker-compose.override.yml` (auto-loaded
alongside `docker-compose.yml`, no flags needed, and excluded from
`deploy.sh`'s rsync so it never reaches the cloud VM) publishes
`litellm`/`boltdiy` straight to host ports. Browsers treat plain
`http://localhost` as a secure context on their own, which is all
bolt.diy's WebContainers actually need — no self-signed cert dance
required. Caddy only turns on when `COMPOSE_PROFILES=cloud` is set in
`.env` (that's what the VM's `.env` has).

Whenever you change `litellm-config.yaml`, `Caddyfile`, or `.env`, remember
mounted config files and env vars are **not** hot-reloaded:
`docker compose restart <service>` after a config-file change,
`docker compose up -d <service>` (a recreate, not just a restart) after an
`.env` value or `docker-compose.yml` itself changes.

## Known quirks (found by running this stack locally before writing it up)

- **A `.env` value containing a literal `$` (a bcrypt Basic Auth hash,
  specifically) breaks `scripts/_env.sh` unless it's single-quoted.** These
  scripts `source` `app/.env` directly (same pattern as
  `docs/alicloud-api-key/scripts/_env.sh`) — that's a real bash parse, not
  a simple KEY=VALUE reader, so an unquoted `NAME=$2a$14$abc...` gets
  bash's own `$2`/`$14`/... positional-parameter expansion applied to it,
  which fails outright under `set -u` ("unbound variable"). Confirmed the
  fix works for both readers that matter: `scripts/generate-team-auth.sh`
  always writes hash values as `NAME='$2a$14$...'` (single-quoted), which
  `source` treats as inert literal text, and separately confirmed via
  `docker compose config` + an actual container's `printenv` that
  Compose's own `.env` parser strips the quotes and hands the container the
  correct unquoted value either way.
- **Gitignore's `!` re-include does not actually un-ignore a genuinely
  untracked file, despite `git check-ignore -v` implying otherwise for
  already-tracked ones.** `app/.gitignore`'s `deepseek-harness/home/*` +
  `!.../.agent-presets/**` pattern (and its `home-team*` copy, added for
  the per-team replication) only reports correctly for paths already in
  git's index — confirmed directly: a brand-new file under a freshly-seeded
  `home-teamN/.agent-presets/` still shows as ignored to `git check-ignore`
  and would be silently skipped by a plain `git add`, negation pattern
  notwithstanding, until it's force-added once (`git add -f
  home-teamN/.agent-presets`). After that one `-f`, it behaves like any
  normally-tracked file. See `app/.gitignore`'s own comment on this.
- **bolt.diy is a custom-built image, not the published one directly.**
  `docker-compose.yml`'s `boltdiy` service builds `Dockerfile.boltdiy`
  (`FROM ghcr.io/stackblitz-labs/bolt.diy:latest` + three patches from
  `patches/`), because the published image has real problems beyond the
  wrangler one below: its provider dropdown shows ~20 mostly-unconfigured
  providers and defaults to Anthropic instead of our actual LiteLLM
  backend; it hardcodes every OpenAI-Like model's output limit to ~8000
  tokens regardless of what the model can really do, which silently chops
  any longer generation (a whole landing page, easily) into several slow
  sequential "continue" calls, sometimes leaving files like `package.json`
  never written; and its "select relevant files" step — a separate LLM
  call that runs mid-turn once a chat has enough history —
  unconditionally crashes the whole request with `Custom error: Bolt
  failed to select files` whenever the model correctly selects zero *new*
  files, which is a normal outcome once the context buffer already has
  what it needs (the model's own instructions explicitly allow an empty
  response in that case). Full writeup, including why a plain bind-mount
  doesn't work and the exact fixes: [docs/bolt-provider-lock/](docs/bolt-provider-lock/).
- **The published `ghcr.io/stackblitz-labs/bolt.diy:latest` image
  crash-loops out of the box** — its `dockerstart` script shells out to
  `wrangler`, which isn't installed in that image. Fixed by installing it
  in `Dockerfile.boltdiy` at build time (was previously a runtime
  `command:` workaround; baking it into the image is both the fix for this
  and a prerequisite for the patches above, since those need a real
  `pnpm run build` to take effect).
- LiteLLM logs `not in built-in cost map` warnings for all three model
  names at startup — harmless. It just means $-cost tracking per token
  defaults to 0 for models it doesn't recognize by name; team budgets
  (set via `max_budget` on the key/team) still enforce correctly by token
  count regardless.
- **A DashScope Hong Kong workspace key only works against that
  workspace's own dedicated endpoint**
  (`https://<workspaceId>.cn-hongkong.maas.aliyuncs.com/compatible-mode/v1`),
  not the shared `dashscope.aliyuncs.com` one (Beijing-region only — a
  Hong Kong key gets a flat `401` there despite being completely valid).
  And the path is `/compatible-mode/v1`, not `/api/v1` — the latter 400s
  with a misleading `BadRequest.EmptyWorkspace` that reads like a
  workspace-binding problem but is really just a wrong URL. See
  [docs/alicloud-api-key/](docs/alicloud-api-key/) for the full debugging
  path and ready-to-run scripts.
- **Open WebUI's env vars only seed config on a genuinely fresh instance —
  once a value's been written to its SQLite `config` table, later env var
  changes are silently ignored on restart.** Bit us twice: `WEBUI_AUTH=False`
  (confirmed working against a truly fresh instance — `/api/config` reports
  `"auth": false`, but re-verify in-browser after any upgrade, since this
  also has its own documented history of not fully applying in some
  versions) and `CODE_INTERPRETER_PROMPT_TEMPLATE` (see next bullet — had to
  be patched directly into the DB with a one-off `sqlite3 UPDATE`, since the
  instance already had real chat history by the time the env var was added,
  and restarting alone didn't pick it up). If a `docker-compose.yml` env var
  change to `open-webui` doesn't seem to be taking effect, this is why —
  either patch the `config` table row directly, or wipe the
  `openwebui_data` volume to force a real fresh seed (loses chat history).
- **Open WebUI's own code interpreter (Pyodide) can't see server files** —
  it runs client-side in-browser, sandboxed, same category of limitation as
  bolt.diy's WebContainers. Real access to `data/` needs the Jupyter
  backend wired in via `CODE_EXECUTION_ENGINE=jupyter` (see
  `docker-compose.yml`'s `open-webui`/`jupyter` services).
- **Code Interpreter is an opt-in toggle per chat, not automatic** — even
  with the backend fully configured, the model only gets the
  `execute_code` tool when the "Code Interpreter" switch (in the message
  input's tools menu, alongside Web Search/Image Generation) is on for that
  chat. Confirmed via `middleware.py`: gated on a `features.code_interpreter`
  flag sent per-message from the frontend, checked independently of the
  backend `code_interpreter.enable` config.
- **Even with the toggle on, the model may still refuse, believing it has
  no server-file access — this is a prompt problem, not a backend one.**
  Open WebUI's *default* code-interpreter system prompt describes it
  generically as running "directly in the user's browser" (accurate for the
  Pyodide engine, false for ours), and its guidance about a persistent
  mounted directory is — per Open WebUI's own source — only ever appended
  for the Pyodide engine, never Jupyter. Left as default, the model reasons
  its way to "the sandbox can't see the user's local files" and refuses
  without ever trying `os.listdir()` — confirmed by reading a real chat's
  own recorded reasoning trace. Fixed via a custom
  `CODE_INTERPRETER_PROMPT_TEMPLATE` (see `docker-compose.yml`) that keeps
  the execution-triggering instructions but corrects the engine description
  and explicitly states `~/data`'s mounted, browsable path.
- **The Code Interpreter toggle can't be defaulted on — confirmed, not just
  unfound.** Checked backend config, an explicit per-model `capabilities`
  declaration (`meta.capabilities.code_interpreter: true` via the `model`
  DB table — Open WebUI's own designed mechanism for model-level defaults),
  and user settings; none affect the per-message toggle's initial state.
  Web Search and Image Generation behave identically. This looks like a
  deliberate always-manual-opt-in UX choice in this version, not a bug or a
  missing setting. Mitigation: `WEBUI_BANNERS` (see `docker-compose.yml`)
  shows an in-app reminder on every chat, since a README note alone won't
  reach participants mid-hackathon.
- **Dify's HTTP Request node silently drops fetched content into a file
  attachment instead of `body` text whenever the response's `Content-Type`
  isn't a text type** — bit us twice on the same fetch, from two different
  layers (nginx's default MIME type for unknown extensions, then a stale
  cache in Dify's own outbound `ssrf_proxy` that kept serving the
  pre-fix response even after nginx was corrected). Also: Dify's Code
  node sandbox is deliberately seccomp-hardened and can't read local files
  even when a path is bind-mounted into it — full write-up, including the
  admin-account bootstrap (no browser wizard needed) and model-provider
  plugin install: [docs/dify-research-agent/](docs/dify-research-agent/).
- **PARKED, unresolved: generated chart images don't render inline in the
  chat**, even with Code Interpreter on and the backend genuinely producing
  and saving valid images (traced multiple charts all the way to real
  bytes on disk — this part works reliably). The model's final visible
  answer just never includes the `![Output Image](...)` markdown the tool
  result contains, describing the chart in prose instead — true across
  every attempt, tightening `CODE_INTERPRETER_PROMPT_TEMPLATE`'s instruction
  to be explicit and non-optional didn't fix it. Next things to try if this
  gets picked back up: check whether the *tool call's own output panel*
  (separate from the model's final message) renders the image somewhere
  not yet checked in the UI; consider that `/api/v1/files/{id}/content`
  requires an authenticated session and a plain markdown-rendered `<img>`
  tag may not carry that auth (cookie-fallback exists in `auth.py` but
  wasn't confirmed working end-to-end — verifying this needs a real
  browser session, which local testing here couldn't simulate without
  forging credentials).

## Tearing down after the event

```bash
cd infra
tofu destroy
```

## Scaling to 5 teams

This started as **one** LiteLLM + **one** bolt.diy instance to prove the
path end to end; `app/docker-compose.yml` now has the full 5-team
replication built in — `boltdiy-team1`..`5` and
`deepseek-harness-team1`..`5` (+ each one's `-proxy` sidecar), plus an
organizer-only `team0` of both. `litellm`, `postgres`, `open-webui`, and
`jupyter` stay single-instance — one shared gateway with per-team budgets
is simpler and more reliable than five gateways, and Open WebUI is a
backup tool now, not a per-team primary (see
[ARCHITECTURE.md](ARCHITECTURE.md#evaluated-not-used) for what else was
evaluated and dropped: Dify, DeerFlow, OpenHands).

Steps to actually stand this up, in order:

1. **Bump the VM size** (already done in this repo's `infra/variables.tf`
   / `terraform.tfvars` — `ecs.g9i.2xlarge`, 8 vCPU/32GB): apply it with
   `cd infra && tofu apply`. This resizes a running instance — expect a
   brief stop/start, not a full destroy/recreate. Do this at a moment
   that can tolerate a minute or two of downtime, not mid-event.
2. **Generate Basic Auth passphrases**: `./scripts/generate-team-auth.sh`
   — writes bcrypt hashes into `app/.env` (`TEAMn_BASIC_AUTH_HASH`,
   `OPENWEBUI_BASIC_AUTH_HASH`) and prints the plaintext passphrases,
   also saved to `app/team-credentials.txt` (gitignored — share these
   with teams out-of-band, e.g. a slide at kickoff, never commit them).
   Safe to run before the VM even exists; re-running only fills in
   whatever's still blank.
3. **Seed each team's DeepSeek Harness home directory** (skip any
   `home-teamN/` that already has a `settings.yaml` — team1's is already
   seeded in this repo):
   ```bash
   cd app/deepseek-harness
   for n in 0 1 2 3 4 5; do
     cp home/settings.yaml "home-team$n/settings.yaml"
     cp -r home/.agent-presets "home-team$n/.agent-presets"
     git add -f "home-team$n/.agent-presets"   # see app/.gitignore's note on why -f
   done
   ```
4. **Point DNS** at the EIP (`tofu -chdir=infra output -raw public_ip`):
   one A record per subdomain Caddy now serves —
   `gateway`, `build0`..`build5`, `team0`..`team5`,
   `analyze`.
5. **Deploy**: `./deploy.sh`. LiteLLM/Caddy/bolt.diy/DeepSeek Harness for
   team1-5 come up; each `boltdiy-teamN` / `deepseek-harness-teamN` 401s
   /misbehaves on model calls until its virtual key is minted (next step).
   `team0` doesn't start at all yet — it's gated behind Compose's
   `organizer` profile (see step 7).
6. **Mint every team's virtual keys**: once the gateway is reachable,
   `./scripts/mint-team-keys.sh https://gateway.<your-domain>` — mints a
   LiteLLM team + a bolt.diy key + a DeepSeek Harness key for team0-5 (12
   keys total) and writes them into `app/.env`. Re-run `./deploy.sh` to
   push the filled-in `.env` and recreate the containers that needed a key.
7. **Organizer testing (`team0`)**, on demand, before/after the event —
   costs nothing while stopped:
   ```bash
   ssh root@<vm-ip> "cd /opt/app && docker compose --profile organizer up -d boltdiy-team0 deepseek-harness-team0 deepseek-harness-team0-proxy"
   # ... test via build0./team0.<your-domain> ...
   ssh root@<vm-ip> "cd /opt/app && docker compose --profile organizer stop boltdiy-team0 deepseek-harness-team0 deepseek-harness-team0-proxy"
   ```
