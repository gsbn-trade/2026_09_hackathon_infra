# Shanghai hackathon — LiteLLM + bolt.diy on AliCloud

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
- OpenTofu installed locally: `brew install opentofu` (installs the `tofu`
  command)
- A domain (or subdomain) you can point DNS at — **required**, not optional:
  bolt.diy's in-browser sandbox (WebContainers) needs a real HTTPS secure
  context to run at all, so a bare IP over `http://` will not work for the
  build track. Caddy handles the certificate automatically once DNS points
  at the VM.
- A Bailian (Model Studio) API key — covers Qwen + DeepSeek + GLM.
- A Moonshot platform API key — Kimi (separate account, not on Bailian).

## 1. Provision the VM

```bash
export ALICLOUD_ACCESS_KEY="..."
export ALICLOUD_SECRET_KEY="..."

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
# (openssl rand -hex 32 for the last two), DASHSCOPE_API_KEY, MOONSHOT_API_KEY
# leave TEAM_VIRTUAL_KEY blank for now
```

Edit `Caddyfile`: replace `gateway.example.com` / `build.example.com` with
your real subdomains.

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
        "models": ["qwen3.7-plus", "deepseek-v4", "glm-4.7", "kimi-k3"]
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

- `https://build.<your-domain>` — open bolt.diy, the model dropdown should
  show `qwen3.7-plus` / `deepseek-v4` / `glm-4.7` / `kimi-k3` under the
  "OpenAI-Like" provider.
- `https://gateway.<your-domain>/ui` — LiteLLM's admin dashboard: spend,
  teams, keys, logs.

## Testing the stack locally first (no AliCloud needed)

Since this is just Docker Compose, you can sanity-check it on your own
machine before ever touching AliCloud — useful for catching config typos
cheaply, and it's the same rehearsal the Mac Mini backup plan relies on:

```bash
cd app
cp .env.example .env   # fill in real provider keys if you want live calls;
                        # containers still boot fine without them
docker compose up -d
curl http://localhost/health/liveliness   # if using the :80 fallback Caddyfile block
```

## Known quirks (found by running this stack locally before writing it up)

- The published `ghcr.io/stackblitz-labs/bolt.diy:latest` image crash-loops
  out of the box — its `dockerstart` script shells out to `wrangler`, which
  isn't installed in that image. `docker-compose.yml` works around it by
  installing `wrangler` at container start; this was verified working, not
  assumed.
- LiteLLM logs `not in built-in cost map` warnings for all four model
  names at startup — harmless. It just means $-cost tracking per token
  defaults to 0 for models it doesn't recognize by name; team budgets
  (set via `max_budget` on the key/team) still enforce correctly by token
  count regardless.

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
