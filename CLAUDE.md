# CLAUDE.md - Claude Code instructions

See README.md for project overview and setup.

## Build & Validate

```bash
shellcheck -x ethd scripts/*.sh
pre-commit run --all-files
cp default.env .env && GENERAL_L1_RPC_URL=https://archive-eth.example.com docker compose config >/tmp/adi-compose.yml
```

## Code Style

- Shell: `set -Eeuo pipefail` in ethd, `set -euo pipefail` in other scripts
- Env vars: `SCREAMING_SNAKE_CASE`, no dashes (breaks bash)
- Env var suffixes: `_TAG` / `_REPO` / `_DOCKERFILE` = build targets (reset by `--refresh-targets`)
- Env var suffixes: `_PORT` for network ports
- Compose services: kebab-case; CLI commands: kebab-case; bash functions: snake_case

## Critical Rules

- Do NOT modify core infrastructure functions in `ethd` — customize only protocol-specific sections marked with comments
- Increment `ENV_VERSION` in `default.env` when adding or renaming variables
- check_sync.sh exit codes: 0=synced, 1=syncing, 2=error/diverged
- New env vars consumed by entrypoint.sh must also be added to the compose `environment:` block
- Test update flow after any env/migration changes: `cp default.env .env && ./ethd update --debug`
- ADI requires an archive Ethereum L1 RPC in `GENERAL_L1_RPC_URL`; pruned L1 endpoints can panic at startup.
- ADI uses port `3050` for both HTTP and WebSocket JSON-RPC.
- ADI mainnet chain ID is fixed at `36900` / `0x9024`; do not make chain-id validation inventory-configurable.
- Persistent node/proof state lives in the `DATA_VOLUME` Docker volume.

## Key Customization Points in ethd

- Header vars: `__project_name`, `__app_name`, `__sample_service`
- Functions: `version()`, `__prep_conffiles()`, `start()`, `__env_migrate()`

## Production References

- Upstream setup repo: `https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script`
- ADI Chainlink setup guide: `https://github.com/smartcontractkit/node-ops-wiki/blob/main/docs/Blockchains/ADI_Setup_Guide.md`
