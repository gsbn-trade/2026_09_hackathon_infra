# Model Studio (Bailian/DashScope) API keys — issue, wire in, debug

How to create and validate the API key `app/litellm-config.yaml`'s model
entries use (`DASHSCOPE_API_KEY`, shared by all five), and how to debug it
fast when something's wrong.
Everything here was learned the hard way getting the first key working —
see "Gotchas" below before you re-derive them yourself.

Scripts live in [`scripts/`](scripts/) and are meant to be run directly:

```bash
cd docs/alicloud-api-key/scripts
./check-permissions.sh        # is this identity even allowed to touch Model Studio?
./list-workspaces.sh          # what workspace(s) exist, what's each one's apiHost?
./list-keys.sh                # what keys already exist, enabled/disabled?
./create-key.sh "description" # mint a new key
./smoke-test-provider.sh      # call Model Studio directly — no LiteLLM/Docker involved
./smoke-test-litellm.sh       # call it through LiteLLM's own /health check
```

They all read `DASHSCOPE_API_KEY`/`LITELLM_MASTER_KEY` from `app/.env` — no
secrets are hardcoded here or printed except a freshly-minted key's value
(unavoidable: Alibaba only shows it once, at creation).

## One-time setup

1. **RAM permission.** The `aliyun` CLI profile used for `infra/`'s
   Terraform only has `AliyunECSFullAccess`/`AliyunVPCFullAccess` — that
   does *not* cover Model Studio. In the
   [RAM console](https://ram.console.alibabacloud.com/users), attach
   **`AliyunBailianControlFullAccess`** to that user (workspace/account/
   API-key management; narrower than `AliyunBailianFullAccess`, which adds
   data-layer permissions this project doesn't need). Verify with
   `check-permissions.sh`.

2. **CLI plugin.** The generic `aliyun modelstudio <ApiName>` form doesn't
   know the actual operation names. Install the dedicated plugin once:
   ```bash
   aliyun plugin install --names aliyun-cli-modelstudio
   ```
   This gives you real subcommands: `aliyun modelstudio create-api-key`,
   `list-workspaces`, `list-api-keys`, etc. `check-permissions.sh` installs
   it automatically if missing.

## Issuing a key

```bash
./create-key.sh "hackathon-2026-08-28"
```

Copy the printed `apiKeyValue` into `app/.env`'s `DASHSCOPE_API_KEY` — it's
shown once and can't be retrieved again later (`list-keys.sh` only ever
shows a masked version). Then:

```bash
cd ../../app   # back to app/
docker compose restart litellm   # env vars are NOT hot-reloaded
```

## Validating a key — cheapest layer first

Test in this order; each layer rules out one more moving part before you
suspect the next:

1. **`smoke-test-provider.sh`** — raw `curl` straight to Model Studio, no
   LiteLLM, no Docker, no bolt.diy. A `200` here means the key + workspace
   + endpoint are unambiguously correct; any failure is 100% provider-side,
   not this repo's config.
2. **`smoke-test-litellm.sh`** — hits LiteLLM's `GET /health`, which makes
   the same kind of test request but *through* LiteLLM using
   `litellm-config.yaml`. Only worth running after step 1 passes — if step
   1 fails, this will too, and step 1's error is more direct.
3. Only after both pass, move up to bolt.diy itself.

The same pattern generalizes to any OpenAI-compatible provider (Moonshot,
etc.) — see the raw `curl` shape inside `smoke-test-provider.sh`.

## Gotchas (all found running this for real — don't re-discover them)

- **The shared `dashscope.aliyuncs.com/compatible-mode/v1` endpoint is
  Beijing-region only.** A Hong Kong-scoped key (like this project's —
  chosen to match `cn-hongkong` hosting) gets a flat `401 invalid_api_key`
  there, even though the key is completely valid. You must use that
  workspace's own **dedicated domain** instead:
  `https://<workspaceId>.<region>.maas.aliyuncs.com/compatible-mode/v1`.
  Find your workspace's exact `apiHost` via `list-workspaces.sh`.

- **The path is `/compatible-mode/v1`, not `/api/v1`.** The dedicated
  domain's console page can make `/api/v1` look plausible, but it 400s with
  `BadRequest.EmptyWorkspace` — a genuinely misleading error, since it
  reads like a workspace-binding problem when it's actually just a wrong
  URL path. A key that's correctly created and workspace-bound (confirm
  with `list-keys.sh`) will still fail here if the path's wrong.

- **No `X-DashScope-Uid` header is needed** on the correct
  `/compatible-mode/v1` path. That header only ever seemed necessary while
  we were on the wrong `/api/v1` path — once the path was fixed, requests
  worked with just a plain `Authorization: Bearer` header.

- **`docker compose up -d` does not pick up `.env` or
  `litellm-config.yaml` changes** for a running `litellm` container — the
  config file is a read-only bind mount and env vars are baked in at
  container creation. Always `docker compose restart litellm` (or
  `up -d --force-recreate litellm`) after changing either.

## Error → cause quick reference

| Error | Cause | Fix |
|---|---|---|
| `401 invalid_api_key` | Endpoint region doesn't match the key's workspace region (e.g. hitting the Beijing shared endpoint with a Hong Kong key) | Use that workspace's dedicated `apiHost` from `list-workspaces.sh` |
| `400 BadRequest.EmptyWorkspace` | Right host, wrong path (`/api/v1` instead of `/compatible-mode/v1`) | Fix the path |
| `403 NoPermission` (on `aliyun modelstudio ...`) | RAM user lacks Model Studio permissions | Attach `AliyunBailianControlFullAccess`, see Setup above |
| `litellm.AuthenticationError` from LiteLLM | Usually the same 401/400 above, just one layer up | Run `smoke-test-provider.sh` first to isolate |
| LiteLLM `/health` shows the old error after a fix | Container wasn't restarted | `docker compose restart litellm` |
