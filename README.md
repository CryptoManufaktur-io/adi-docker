# ADI Docker

Docker Compose deployment for an [ADI Chain](https://adi.foundation/) mainnet external node, used by Galaxy for self-hosted RPC behind Chainlink CCIP.

This is adi-docker v0.1.0

## What it runs

ADI is a zkSync-based zk-rollup L2. The external node is read-only — it replays L2 blocks locally and serves a standard JSON-RPC interface. Three containers run as part of this stack:

| Service | Image | Role |
|---|---|---|
| `init-data` | `busybox:1.36.1` | One-shot — creates `/chain/db/node1/block_dumps` and `/chain/db/shared` and chmods them |
| `proof-sync` | `peterdavehello/azcopy:10.27.1` | Periodically `azcopy sync` from `adimainnet.blob.core.windows.net/proofs` to `/chain/db/shared` |
| `node` | `harbor.sre.ideasoft.io/adi-chain/external-node:v0.13.0-b1` | ADI external node — JSON-RPC + WS on `:3050`, status on `:3071`, replay on `:3054`, metrics on `:3312` |

Upstream reference: <https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script>
Galaxy runbook: <https://github.com/smartcontractkit/node-ops-wiki/blob/main/docs/Blockchains/ADI_Setup_Guide.md>

## Hardware

| Component | Recommended |
|---|---|
| CPU | 16 cores |
| RAM | 32 GB |
| Storage | 500+ GB NVMe |

Initial sync takes roughly 1 day.

## Required configuration

`GENERAL_L1_RPC_URL` **must** point at an **archive** Ethereum L1 RPC. Pruned L1 endpoints will cause startup panics with `state at block is pruned`. Set this per host in the Ansible inventory.

## Quick start (local / non-Ansible)

```bash
cp default.env .env
# edit .env: at minimum set GENERAL_L1_RPC_URL to an archive L1 RPC
./adid up -d
./adid logs -f node
./adid check-sync
```

## Operational commands

| Command | Action |
|---|---|
| `./adid up [-d]` | Start the stack |
| `./adid down` | Stop and remove containers (volume preserved) |
| `./adid logs [-f] [service]` | Follow logs |
| `./adid version` | Print container image versions |
| `./adid check-sync` | Compare local block height against `https://rpc.adifoundation.ai` |
| `./adid update` | Rebuild env from `default.env` and pull updated images |

## Production deployment

This repo is deployed via [`cmf-ansible`](https://github.com/GalaxyBlockchainEngineering/cmf-ansible) with config in [`cmf-ansible-inventory`](https://github.com/GalaxyBlockchainEngineering/cmf-ansible-inventory) under `production/chainlink_inventory.yml`. Traefik routes:

- `adi-a.cryptomanufaktur.net` / `adiws-a.cryptomanufaktur.net` → rpc7-a
- `adi-c.cryptomanufaktur.net` / `adiws-c.cryptomanufaktur.net` → rpc7-c

## Ports

| Port | Purpose | Exposed by `rpc-shared.yml` |
|---|---|---|
| 3050 | JSON-RPC HTTP + WebSocket (ADI multiplexes both) | yes, `127.0.0.1` |
| 3054 | Sequencer block replay server | no |
| 3071 | Status / health server | no |
| 3312 | Prometheus `/metrics` | no |

## Image pinning

All image tags are pinned in `default.env`. Bump deliberately; do not use `latest`. Upstream `EN_VERSION` is currently `v0.13.0-b1` for mainnet.
