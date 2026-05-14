# CLAUDE.md — Claude Code instructions

See README.md for project overview, deployment, and ports.

## Build & Validate

```bash
shellcheck -x ethd scripts/check_sync.sh scripts/sync-proofs.sh
pre-commit run --all-files
./adid help
./adid -h
cp default.env .env && ./adid check-sync; rm .env
```

## Code Style

- Shell: `set -Eeuo pipefail` in `ethd`, `set -euo pipefail` in other scripts.
- Env vars: `SCREAMING_SNAKE_CASE`, no dashes (breaks bash interpolation).
- Env var suffixes: `_TAG` / `_REPO` / `_DOCKERFILE` = build targets (reset by `--refresh-targets`); `_PORT` for network ports.
- Compose services: kebab-case; CLI commands: kebab-case; bash functions: snake_case.
- Increment `ENV_VERSION` in `default.env` whenever you add or rename a variable.
- Never capture into `local` with command substitution on the same line — `local` always returns 0, masking the inner failure. Use `local foo; foo=$(...) || exit N` instead.

## Critical rules

- `GENERAL_L1_RPC_URL` must be an **archive** Ethereum L1 RPC. Pruned L1 panics on startup with `state at block is pruned`.
- All image tags (`NODE_DOCKER_TAG`, `AZCOPY_DOCKER_TAG`, `BUSYBOX_DOCKER_TAG`) are pinned in `default.env`. Never replace with `latest`.
- `init-data` must run to completion before `proof-sync` and `adi` start — it creates `/chain/db/node1/block_dumps` and `/chain/db/shared` and chmods them `0777`. Do not remove the `depends_on` chain.
- `RPC_PORT` (3050) multiplexes both JSON-RPC HTTP and WebSocket. Both `RPC_LB` and `WS_LB` Traefik load balancers point at this single port.
- `adi.yml` `mem_limit: 28g` reserves headroom on shared rpc7 hosts; do not unset without coordinating with other chains on the host.
- Healthcheck `start_period: 15m` accommodates cold start (L1 watcher may block up to 600s waiting for `proof_storage`).
- `check_sync.sh` exit codes: `0=synced, 1=syncing, 3=local RPC error, 4=public RPC error, 5=config error, 6=missing deps, 7=container error`. Exit code `2` (diverged) is intentionally not emitted — for ADI external nodes, the public RPC IS the main node, so divergence is structurally impossible.
- Compose `${...}` interpolation conflicts with shell `${...}`. Escape shell parameter expansion in healthchecks etc. with `$$` (e.g. `$${#payload}`).

## Traefik labels

- `traefik.docker.network=${DOCKER_EXT_NETWORK}` is intentionally omitted. ADI's stack joins both `default` and `ext-network`; Traefik picks the network reachable from itself. If Traefik later starts routing to the wrong subnet, add the label.
- `RPC_LB` and `WS_LB` both target `${RPC_PORT}` (3050) because ADI multiplexes HTTP and WS on the same port — this is not a typo.

## Compose overlays

- `default.env` `COMPOSE_FILE=adi.yml:rpc-shared.yml` — local dev, exposes 3050 on `127.0.0.1` so `./adid check-sync` works from the host.
- Production inventory overrides to `COMPOSE_FILE: "adi.yml:ext-network.yml"` — no `rpc-shared.yml`, traffic comes in only over Traefik.

## Customization points in ethd

- Header vars (`__project_name`, `__app_name`, `__sample_service`) — already set to ADI.
- `version()` — prints container image tags for `adi` and `proof-sync`.
- `__prep_conffiles()` — no-op for ADI; genesis is bind-mounted from `genesis/mainnet.json`.

## Upstream sources

- Setup script: <https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script>
- ADI docs: <https://docs.adi.foundation/>
- Node-ops wiki entry: <https://github.com/smartcontractkit/node-ops-wiki/blob/main/docs/Blockchains/ADI_Setup_Guide.md>

When `EN_VERSION` bumps upstream, update `NODE_DOCKER_TAG` in `default.env` and the README image table; verify the digest with the Harbor token-auth endpoint before pinning.
