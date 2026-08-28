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
- A Bailian (Model Studio) API key — covers Qwen + DeepSeek + GLM.
- A Moonshot platform API key — Kimi (separate account, not on Bailian).

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
  -d '{"model": "qwen3.7-plus", "messages": [{"role":"user","content":"ping"}]}'
```

If a model 404s, its id likely shifted on Bailian's side — check the Model
Square in the Bailian console and fix the string in `app/litellm-config.yaml`,
then `./deploy.sh` again.

## 5. Mint a team virtual key

```bash
curl https://gateway.<your-domain>/key/generate \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
        "team_id": "team-1",
        "max_budget": 20,
        "models": ["qwen3.7-plus", "kimi-k2.7-code", "deepseek-v4-flash-0731"]
      }'
```

(Create the team first with `POST /team/new` if you want team-level budget
aggregation across multiple keys — for a single test key this step alone is
enough.) Take the returned `key` value, put it in `app/.env` as
`TEAM_VIRTUAL_KEY`, then:

```bash
./deploy.sh
```

## 6. Use it

- `https://build.<your-domain>` — open bolt.diy. OpenAI-Like is the only
  provider and is pre-selected (patched, see Known quirks below); the model
  dropdown should show `qwen3.7-plus` / `kimi-k2.7-code` /
  `deepseek-v4-flash-0731`.
- `https://analyze.<your-domain>` — Open WebUI, for data understanding
  before building: chat + a real Python/pandas code interpreter (Jupyter
  backend) with every `data/` track mounted read-only at `~/data` — no
  upload needed, `pd.read_csv('data/Track 1 - Vessel Schedule/bookings.csv')`
  just works. No login required (`WEBUI_AUTH=False`, same "just open the
  URL" pattern as bolt.diy).
- `https://gateway.<your-domain>/ui` — LiteLLM's admin dashboard: spend,
  teams, keys, logs.

Needs its own `OPENWEBUI_VIRTUAL_KEY` minted the same way as step 5's
`TEAM_VIRTUAL_KEY` (separate key so its spend/budget tracks independently),
plus `OPENWEBUI_SECRET_KEY` and `JUPYTER_TOKEN` (`openssl rand -hex 32` /
`-hex 24`) in `app/.env` — see `.env.example`. Needs its own DNS A record
for `analyze.<your-domain>` too, same as `gateway`/`build`.

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

- **bolt.diy is a custom-built image, not the published one directly.**
  `docker-compose.yml`'s `boltdiy` service builds `Dockerfile.boltdiy`
  (`FROM ghcr.io/stackblitz-labs/bolt.diy:latest` + two patches from
  `patches/`), because the published image has two real problems beyond
  the wrangler one below: its provider dropdown shows ~20 mostly-
  unconfigured providers and defaults to Anthropic instead of our actual
  LiteLLM backend, and it hardcodes every OpenAI-Like model's output limit
  to ~8000 tokens regardless of what the model can really do — which
  silently chops any longer generation (a whole landing page, easily) into
  several slow sequential "continue" calls, sometimes leaving files like
  `package.json` never written. Full writeup, including why a plain
  bind-mount doesn't work and the exact fix: [docs/bolt-provider-lock/](docs/bolt-provider-lock/).
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

## Scaling from this one test instance to the full 5-team setup

This repo intentionally deploys **one** LiteLLM + **one** bolt.diy instance
to prove the path end to end. For the event itself: bump `instance_type` up
a size, replicate the `boltdiy` (and `openwebui`) service block per team
with each team's own virtual key baked into its environment, and give each
its own Caddy subdomain (`build-team1.`, `build-team2.`, …) — same pattern
as the `litellm` service above of environment-only forking, no new
OpenTofu needed unless you split it across a second VM for OpenHands.
