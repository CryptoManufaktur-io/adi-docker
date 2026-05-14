# ADI Docker

Docker Compose deployment for an [ADI Chain](https://adi.foundation/) mainnet external node, used by Galaxy for self-hosted RPC behind Chainlink CCIP.

This is adi-docker v0.1.0

## What it runs

ADI is a zkSync-based zk-rollup L2. The external node is read-only — it replays L2 blocks locally and serves a standard JSON-RPC interface. Three containers run as part of this stack:

| Service | Image | Role |
|---|---|---|
| `init-data` | `busybox:1.36.1` | One-shot — creates `/chain/db/node1/block_dumps` and `/chain/db/shared`, chmods them `0777` |
| `proof-sync` | `peterdavehello/azcopy:10.27.1` | Periodically `azcopy sync` from `adimainnet.blob.core.windows.net/proofs` into `/chain/db/shared` |
| `adi` | `harbor.sre.ideasoft.io/adi-chain/external-node:v0.13.0-b1` | ADI external node — JSON-RPC + WS on `:3050`, status on `:3071`, replay on `:3054`, metrics on `:3312` |

Upstream reference: <https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script>
Galaxy runbook: <https://github.com/smartcontractkit/node-ops-wiki/blob/main/docs/Blockchains/ADI_Setup_Guide.md>

## Hardware

| Component | Recommended |
|---|---|
| CPU | 16 cores |
| RAM | 32 GB (compose enforces `mem_limit: 28g`) |
| Storage | 500+ GB NVMe |

Initial sync takes roughly 1 day.

## Required configuration

`GENERAL_L1_RPC_URL` **must** point at an **archive** Ethereum L1 RPC. Pruned L1 endpoints panic on startup with `state at block is pruned`. In production this is set per host in the Ansible inventory; for local runs, export it before `./adid up`.

## Quick start (local / non-Ansible)

```bash
cp default.env .env
# edit .env: at minimum set GENERAL_L1_RPC_URL to an archive Ethereum RPC
./adid up -d
./adid logs -f adi
# wait ~15 minutes for the healthcheck to flip from starting to healthy
./adid check-sync
```

## Operational commands

| Command | Action |
|---|---|
| `./adid up [-d]` | Start the stack |
| `./adid down` | Stop and remove containers (volume preserved) |
| `./adid logs [-f] [service]` | Follow logs (services: `adi`, `proof-sync`, `init-data`) |
| `./adid version` | Print container image versions |
| `./adid check-sync` | Compare local block height against `https://rpc.adifoundation.ai`, also asserts `eth_syncing=false` |
| `./adid update` | Rebuild env from `default.env` and pull updated images |
| `./adid terminate` | Stop and destroy all data volumes (irreversible) |

## Compose overlays

- `default.env` ships with `COMPOSE_FILE=adi.yml:rpc-shared.yml` so the local dev workflow can hit `http://127.0.0.1:3050`.
- Production (via `cmf-ansible-inventory`) overrides this to `COMPOSE_FILE=adi.yml:ext-network.yml` — no `127.0.0.1` binding; traffic comes in over Traefik vhosts.

## Production deployment

Deployed via [`cmf-ansible`](https://github.com/GalaxyBlockchainEngineering/cmf-ansible) with config in [`cmf-ansible-inventory`](https://github.com/GalaxyBlockchainEngineering/cmf-ansible-inventory) under `production/chainlink_inventory.yml`. Traefik routes:

- `adi-a.cryptomanufaktur.net` / `adiws-a.cryptomanufaktur.net` → rpc7-a
- `adi-c.cryptomanufaktur.net` / `adiws-c.cryptomanufaktur.net` → rpc7-c

Traefik load balancers `adi-lb` / `adiws-lb` fan out across the per-region instances.

## Ports

| Port | Purpose | Exposed by `rpc-shared.yml` | Notes |
|---|---|---|---|
| 3050 | JSON-RPC HTTP + WebSocket (ADI multiplexes both) | yes, `127.0.0.1` | Public over Traefik in prod |
| 3054 | Sequencer block replay server | no | Host-internal only |
| 3071 | Status / health server | no | Host-internal only |
| 3312 | Prometheus `/metrics` | no | Scraped by prom_cluster on the same host |

## Image pinning

All image tags are pinned in `default.env`. Bump deliberately; do not use `latest`. Upstream `EN_VERSION` is currently `v0.13.0-b1` for mainnet.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Failed to load genesis upgrade transaction: ... state at block is pruned` panic | `GENERAL_L1_RPC_URL` points at a non-archive Ethereum endpoint | Replace with an archive L1 RPC |
| `Data not found in storage, will retry ... committed batch ... in proof storage` warnings during boot | `proof-sync` hasn't downloaded enough yet (normal on cold start, can run up to 600s) | Wait for first azcopy cycle to finish populating `/chain/db/shared` |
| `proof-sync` keeps logging `azcopy sync failed with exit code N` | Network outage or auth issue to `adimainnet.blob.core.windows.net` | Check sidecar logs (`./adid logs proof-sync`); endpoint is public anonymous read so usually transient |
| Healthcheck stays `starting` past 15 minutes | Slow disk, insufficient RAM, or L2 replay lag from cold genesis | `./adid logs adi`; if RocksDB is busy persisting blocks, just wait. If memory pressure is real, bump `mem_limit`. |
| `./adid logs adi` shows `Connection refused` to `general_l1_rpc_url` | Inventory L1 endpoint down or wrong URL | Verify the L1 host is reachable; check ansible secret rendering |

## Resource limits

Compose sets `mem_limit: 28g` and `mem_reservation: 16g` on the `adi` service to fence it on shared rpc7 hosts. `stop_grace_period: 20m` allows RocksDB to flush cleanly on shutdown.
