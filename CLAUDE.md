# CLAUDE.md — Claude Code instructions

See README.md for project overview, ports, troubleshooting, compose overlays, and upstream links.

## Build & Validate

```bash
shellcheck -x ethd scripts/check_sync.sh scripts/sync-proofs.sh
pre-commit run --all-files
./adid help && ./adid -h
cp default.env .env && ./adid check-sync; rm .env
```

## Code Style

- Shell: `set -Eeuo pipefail` in `ethd`, `set -euo pipefail` in other scripts.
- Env vars: `SCREAMING_SNAKE_CASE`, no dashes (breaks bash interpolation).
- Suffixes: `_TAG` / `_REPO` / `_DOCKERFILE` mark build targets (reset by `--refresh-targets`); `_PORT` for network ports.
- Compose services: kebab-case; CLI commands: kebab-case; bash functions: snake_case.
- Never capture into `local` with a command substitution on the same line — `local` always returns 0 and masks the inner failure. Use `local foo; foo=$(...) || exit N`.
- Increment `ENV_VERSION` in `default.env` whenever you add or rename a variable.

## Critical rules

- `GENERAL_L1_RPC_URL` must be an **archive** Ethereum L1 RPC. Pruned L1 panics with `state at block is pruned`.
- All image tags in `default.env` are pinned; never replace with `latest`.
- `proof-sync` runs `scripts/sync-proofs.sh`, which creates `/chain/db/node1/block_dumps` and `/chain/db/shared` (chmod `0777`) before the azcopy loop. The `adi` service `depends_on: proof-sync` — do not remove.
- `RPC_PORT` 3050 multiplexes HTTP **and** WebSocket; both `RPC_LB` and `WS_LB` Traefik services target this single port (not a typo).
- `PUBLIC_RPC_URL` doubles as the external node's `general_main_node_rpc_url` and `check_sync.sh`'s reference RPC — same URL; do not split into two variables.
- `check_sync.sh` exit codes: `0=synced, 1=syncing, 3=local RPC error, 4=public RPC error, 5=config error, 6=missing deps, 7=container error`. Code `2` (diverged) is intentionally not emitted (public RPC IS the main node).
- Compose `${...}` interpolation conflicts with shell `${...}`; escape shell parameter expansion with `$$` (e.g. `$${#payload}`).
- `traefik.docker.network=${DOCKER_EXT_NETWORK}` is intentionally omitted. If Traefik later routes to the wrong subnet, add it back.

## Bumping the image

When upstream `EN_VERSION` bumps (`docker-compose.mainnet.yml` in `ADI-Foundation-Labs/ADI-Stack-EN-Setup-script`): update `NODE_DOCKER_TAG` in `default.env` and the README image table. Verify the new tag's digest via the Harbor token-auth endpoint before pinning.

## ethd customization points

- `__project_name`, `__app_name`, `__sample_service` — already set to ADI.
- `version()` — prints `adi` and `proof-sync` image tags.
- `__prep_conffiles()` — no-op; genesis is bind-mounted from `genesis/mainnet.json`.
