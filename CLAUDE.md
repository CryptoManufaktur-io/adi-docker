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

## Critical rules

- `GENERAL_L1_RPC_URL` must be an **archive** Ethereum L1 RPC. Pruned L1 panics on startup with `state at block is pruned`.
- All image tags (`NODE_DOCKER_TAG`, `AZCOPY_DOCKER_TAG`, `BUSYBOX_DOCKER_TAG`) are pinned in `default.env`. Never replace with `latest`.
- `init-data` must run to completion before `proof-sync` and `node` start — it creates `/chain/db/node1/block_dumps` and `/chain/db/shared` and chmods them 0777. Do not remove the `depends_on` chain.
- `RPC_PORT` (3050) carries both JSON-RPC HTTP and WebSocket. Both `RPC_LB` and `WS_LB` Traefik services point at this single port.
- `check_sync.sh` exit codes: 0=synced, 1=syncing, 3=local RPC error, 4=public RPC error, 5=config error, 6=dep error, 7=container error.
- Increment `ENV_VERSION` in `default.env` when adding or renaming variables.

## Customization points in ethd

- Header vars (`__project_name`, `__app_name`, `__sample_service`) — already set to ADI.
- `version()` — prints container image tags for `node`, `proof-sync`.
- `__prep_conffiles()` — no-op for ADI; genesis file is bind-mounted from `genesis/mainnet.json`.

## Upstream sources

- Setup script: <https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script>
- ADI docs: <https://docs.adi.foundation/>
- Node-ops wiki entry: <https://github.com/smartcontractkit/node-ops-wiki/blob/main/docs/Blockchains/ADI_Setup_Guide.md>

When `EN_VERSION` bumps upstream, update `NODE_DOCKER_TAG` in `default.env` and the README image table; verify the digest with the Harbor token-auth endpoint before pinning.
