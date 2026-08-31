# DeepSeek Harness (dsh) — installed from the published npm package, not
# built from source (unlike app/deerflow/, dsh ships as a normal npm
# release; no from-source build needed). Pinned to an exact version, not
# @latest — upstream's own README: "developer preview... THERE WILL BE
# COMPATIBILITY-BREAKING CHANGES."
#
# A from-source build (to get the experimental Agent Teams feature — true
# peer-to-peer teammates + a shared task board, see
# ../../docs/deepseek-harness/README.md) was attempted and reverted: the
# repo's own `pnpm dsh` dev command (`node --import tsx/esm
# apps/cli/src/bin.ts`) fails outside their own dev environment with
# `SyntaxError: The requested module '@deepseek-ai/cordis' does not provide
# an export named 'FiberState'` — `FiberState` is declared `export const
# enum FiberState` in vendor/cordis/src/fiber.ts, which TypeScript fully
# erases at build time by design; tsx/esbuild transpiles each file without
# cross-file type information, so it can't tell the erasure was intentional
# and treats the import as a missing runtime export. Not a Dockerfile fix —
# see docs/deepseek-harness/README.md's "Tier 2" section for the full
# diagnosis and what to try if this gets picked back up.
#
# node:22-slim (Debian), not -alpine — dsh's workspace-write
# permission preset uses a host sandbox backend (bwrap/Landlock) that's
# more predictable on glibc than musl for this kind of native-process
# isolation tooling.
FROM node:22-slim

RUN npm install -g @deepseek-ai/dsh@0.1.1-rc.2

# All harness user data (settings.yaml, credentials, session/profile state)
# — bind-mounted from ./home so it survives container recreation. See
# ../docker-compose.yml's deepseek-harness service.
ENV DSH_HOME=/data/.dsh
# Feedback-gated by default upstream (nothing uploaded until a user runs
# /feedback) — disabled outright here anyway, matching this repo's general
# carefulness about what leaves the VM.
ENV DSH_TELEMETRY_MODE=DISABLED

WORKDIR /workspace

# --no-open: no display in a container: this only stops it from trying to
# launch a local browser, it does not change binding. dsh's own CLI hardcodes
# the web server to 127.0.0.1 and exits with a usage error on --host
# 0.0.0.0 — a deliberate safety choice (a session gets real bash/filesystem
# access with only a click-to-approve gate, no login wall) — see
# ../../docs/deepseek-harness/README.md for how this is reached anyway.
CMD ["dsh", "web", "--no-open"]
