# Dify: self-hosted deployment + Track Research Agent template

**Status: implemented and confirmed working 2026-08-28.** Full write-up of
how Dify is deployed (reusing the main stack's Postgres instead of its own
bundled DB/vector-store containers), how the admin account was bootstrapped
without the browser setup wizard, and the two-layer caching bug that made
the template research workflow return blank content on its first "working"
run. Like the other `docs/*` write-ups, this is a record of *why*, not a
live TODO.

## Deployment approach

Dify's `docker/` directory is vendored into `app/dify/` via a sparse
checkout of `langgenius/dify` (`git clone --depth 1 --filter=blob:none
--sparse`, then `sparse-checkout set docker`) — **not** hand-edited. All
local changes live in `app/dify/docker-compose.override.yml` (auto-loaded,
same pattern as `app/docker-compose.override.yml`) and `app/dify/.env`, so a
future re-vendor is a clean `git diff` against upstream instead of untangling
hand-edits.

### Reusing Postgres instead of Dify's bundled DB + vector store

`app/docker-compose.yml`'s `postgres` service image was swapped from
`postgres:16` to `pgvector/pgvector:pg16` — a drop-in-compatible build with
the pgvector extension added, same `PGDATA` format, no migration needed for
the existing `litellm` database. Two more databases were created on that
same server for Dify: `dify` (relational + vector store, via the `vector`
extension) and `dify_plugin`. `.env`'s `COMPOSE_PROFILES=` (emptied out) and
`VECTOR_STORE=pgvector` skip Dify's own bundled Postgres/Weaviate/Redis
containers entirely — one Postgres server instead of running two, one set of
backup/ops procedures.

`REDIS_HOST=redis` also points at the main stack's Redis rather than
spinning up a second one — same reasoning.

### Cross-project networking

Dify (`app/dify/`) and the main stack (`app/`) are two separate Compose
projects, connected by an external `hackathon_shared` network (created once
via `docker network create hackathon_shared`; `deploy.sh` does this
automatically, idempotently). `docker-compose.override.yml` adds
`hackathon_shared` to every Dify service that needs to reach
`postgres`/`litellm` by name: `api`, `worker`, `worker_beat`,
`plugin_daemon`, `ssrf_proxy` (the actual egress point for `api`/`worker`'s
outbound calls — see the SSRF proxy allowlist note below), and `nginx`
(what the main stack's Caddy will reverse-proxy to in the cloud deploy,
instead of Dify's `nginx` publishing 80/443 directly and conflicting with
Caddy's).

`EXPOSE_NGINX_PORT=8081` in `.env` is how the host port is set — **not** a
`ports:` override in the override file. Compose merges list fields
(`ports`, `volumes`) across compose files rather than replacing them, so an
attempted `ports:` override there would have *added* to the base file's
`80:80` rather than replacing it (confirmed the hard way — still showed
`0.0.0.0:80->80` after "overriding" it). The base file's `ports:` entry is
already `${EXPOSE_NGINX_PORT:-80}:...`, so setting the env var sidesteps the
merge behavior instead of fighting it.

### SSRF proxy allowlist

Dify routes `api`/`worker`'s outbound HTTP (including calls to LiteLLM and
Postgres-adjacent services) through its own `ssrf_proxy` (squid), which by
default blocks requests to private IP ranges. `SSRF_PROXY_ALLOW_PRIVATE_IPS`
in `.env` had to include `172.22.0.0/16` (the `hackathon_shared` subnet) —
without it, every internal call to `litellm` or `data-server` silently
fails as an SSRF block, not an obviously-labeled error.

## First-time local setup

`app/dify/.env` and `app/dify/volumes/sandbox/conf/config.yaml` are both
gitignored (real secrets, same pattern as the main stack's `.env`). Before
first `docker compose up`:

1. Copy `app/dify/.env.example` → `.env` and fill in real values (DB
   credentials matching `postgres`, `SANDBOX_API_KEY`,
   `PLUGIN_DAEMON_KEY`, etc. — see "Reusing Postgres" and "SSRF proxy
   allowlist" above for the non-obvious ones).
2. Copy `app/dify/volumes/sandbox/conf/config.yaml.example` →
   `config.yaml` and set `app.key` to the **same value** as `.env`'s
   `SANDBOX_API_KEY`. This one can't just read the `.env` value at
   runtime — it's a plain volume mount, not passed through Compose's env
   substitution — so the two have to be kept in sync by hand.

## Admin account bootstrap (no browser setup wizard)

Dify's normal first-run flow is a browser wizard at `/install` that POSTs a
client-side-RSA-encrypted password to `/console/api/setup`. That's not
scriptable from `curl` without replicating the frontend's encryption step,
so the account and the system-wide "setup complete" flag were both created
directly instead:

1. **Account + tenant**: `docker exec -i <api-container> flask
   create-tenant --email <email> --name "<workspace name>"` — must be run
   with `-i` (stdin attached) or it aborts. This command itself required
   `ALLOW_REGISTER=true` and `ALLOW_CREATE_WORKSPACE=true` in `.env` (both
   default `false`); without them it fails with `AccountNotFound` and then
   `WorkSpaceNotAllowedCreateError` respectively. It prints a
   password on success — save it, it's not shown again.
2. **System setup flag**: `create-tenant` does *not* mark the system as
   set up — logging in still returned `{"code":"not_setup"}`. Dify checks
   a `dify_setups` table (`version`, `setup_at`, `instance_id`), written by
   `SetupService.mark_setup_completed()`. Inserted directly:
   ```sql
   INSERT INTO dify_setups (version, setup_at, instance_id)
   VALUES ('<dify_config.project.version>', now(), gen_random_uuid()::text);
   ```
   Confirmed via `GET /console/api/setup` flipping from `{"step":"not_started"}`
   to `{"step":"finished",...}`.

Login itself still needs a real browser (the password field is RSA-encrypted
client-side before submission — a plain `curl` POST with a plaintext
password will always get `{"code":"authentication_failed","message":"Invalid
encrypted data"}`, which is expected, not a bug).

## Model provider: plugin install + credential wiring

Dify 1.x moved model providers to a plugin system (`plugin_daemon`
service, packages fetched from `https://marketplace.dify.ai`) — nothing is
pre-installed, including the generic `openai_api_compatible` provider
needed to point at LiteLLM. Installed via the Flask app context
(`PluginService.install_from_marketplace_pkg`, after resolving the
package's versioned identifier through
`core.helper.marketplace.batch_fetch_plugin_by_ids`), polling
`PluginService.fetch_install_task` until `status: success`. Credentials
were then created via `ModelProviderService.create_model_credential` —
**every numeric field must be passed as a string** (`context_size:
'131072'`, not `131072`) or it raises `TypeError: Variable context_size
should be string`.

### Embeddings are unavailable in this workspace

`text-embedding-v4` is listed in the Bailian model catalog but returns
`Model.Unsupported` / `Model is not supported in current workspace service
site` when actually called against this Hong Kong workspace's dedicated
endpoint — confirmed against both the OpenAI-compatible and native
DashScope embedding paths. This is a genuine deployment gap on the provider
side, not a config bug. Decision: skip Knowledge Base / vector retrieval
entirely and use **full-text inclusion** instead — the template workflow
below fetches a track's whole `brief.md` (a few KB) straight into the LLM
prompt rather than chunking+embedding it. Revisit only if a workspace with
embeddings deployed becomes available.

## The sandbox can't read local files — use `data-server` instead

Dify's Code node executor (`dify-sandbox`) is deliberately seccomp-hardened
and returns `operation not permitted` on local file access even when a path
is bind-mounted into the container — confirmed directly against
`dify-sandbox`'s own `POST /v1/sandbox/run` API, not just from within a
workflow. This is by design (arbitrary user-authored Python shouldn't get
host file access), not a missing-mount problem, so mounting `data/` into
`sandbox` (as `docker-compose.override.yml` briefly did) is dead
configuration and was removed.

The actual working path: `app/docker-compose.yml` runs a plain internal
`data-server` (nginx, no host port, no Caddy route) serving `../data` —
`app/data-server.nginx.conf`. Workflows fetch a track's `brief.md` with an
**HTTP Request node**, not a Code node.

### Two content-type gotchas that both silently blanked the fetched content

The HTTP Request node treats any *non-text* `Content-Type` response as a
file attachment (populates the node's `files` output) rather than text
(leaves `body` empty) — confirmed in `core/workflow/nodes/http_request/
node.py`. Two independent things served the wrong content type here, and
both had to be fixed before `{{#http_node.body#}}` actually carried real
text into the LLM prompt:

1. **nginx's default MIME map has no `.md` entry**, so it served every
   brief as `application/octet-stream`. Fixed with a `default_type
   text/plain;` directive in `data-server.nginx.conf` — **must be inside
   the `server {}` block, not at the file's top level**: the base image's
   own `nginx.conf` already sets `default_type` at the `http{}` level this
   `conf.d` file gets included into, so a second top-level directive here
   is a fatal `"default_type" directive is duplicate` (confirmed the hard
   way — crash-looped on start).
2. **Even after nginx was fixed, the workflow still returned blank
   content.** Dify's `ssrf_proxy` (squid) sits in front of every outbound
   call `api`/`worker` make, including this one, and it caches responses —
   it had cached the *old* `application/octet-stream` response from before
   the nginx fix and kept serving that (`Cache-Status: hit`) rather than
   re-fetching. Diagnosed by checking the actual `http_node` output row in
   `workflow_node_executions` (`content-type` and `cache-status` headers
   are recorded there) rather than trusting a plain `curl` against
   `data-server` directly, which only tests nginx and never goes through
   squid at all. Fixed with `docker compose restart ssrf_proxy
   agent_ssrf_proxy` to drop the stale cache entry — confirmed via
   `Cache-Status: ...;detail=mismatch` (a real re-fetch) on the next
   request, then by re-running the workflow and getting a real,
   fully-grounded answer instead of "the Track Briefing text provided is
   empty."

If this ever regresses (blank `body` on an HTTP node that should have
content), check both layers independently: `curl -sI` straight to
`data-server` for the `Content-Type`, and — since that bypasses the proxy
entirely — a real workflow run's `workflow_node_executions.outputs` (or
`curl -x http://ssrf_proxy:3128 ...` from inside the `api` container) for
what squid actually served.

## The template workflow

[`track_research_agent.yml`](track_research_agent.yml) — a 4-node Dify
workflow app (`Start → HTTP Request → LLM → End`):

- **Start**: `track` (select, one of the 5 track folder names under
  `data/`), `question` (free text).
- **HTTP Request**: `GET http://data-server/{{#start_node.track#}}/brief.md`
  — no auth, internal network only.
- **LLM**: `langgenius/openai_api_compatible/openai_api_compatible` →
  LiteLLM, `qwen3.7-plus`. System prompt sets up a research-analyst persona
  instructed to ground every claim in the fetched briefing and structure the
  answer as (1) problem summary, (2) direct answer, (3) a buildable product
  angle sized for a half-day hackathon build. User prompt is just
  `TRACK BRIEFING:\n{{#http_node.body#}}\n\nQUESTION:\n{{#start_node.question#}}`.
- **End**: outputs `answer` = the LLM's text.

To use: import the YAML in Dify's app list ("Import DSL"), then **publish
the draft** — an imported workflow exists as a draft only and won't run via
the normal app-run APIs until explicitly published from the workflow
editor. Duplicate this app per team and adjust the model/prompt as needed;
each team's copy can be swapped to a different provider/model without
touching the HTTP node.
