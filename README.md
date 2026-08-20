# ADI Docker

Docker Compose deployment for an [ADI Chain](https://adi.foundation/) mainnet external node.

This is adi-docker v0.1.0

## What it runs

ADI is a zkSync-based zk-rollup L2. The external node is read-only — it syncs over P2P (devp2p) from peers and serves a standard JSON-RPC interface. Single container:

| Service | Image | Role |
|---|---|---|
| `adi` | `harbor.sde.adifoundation.ai/ghpc/adi-foundation-labs/server:v0.20.12-b1` | ADI external node — JSON-RPC + WS on `:3050`, status on `:3071`, P2P on `:3060` (TCP+UDP), metrics on `:3312` |

As of v0.20.12, ENs sync via P2P instead of downloading HTTP block replays, and no longer use proof storage — the old `proof-sync` sidecar (azcopy against Azure Blob) is gone.

- Upstream setup script: <https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script>
- ADI docs: <https://docs.adi.foundation/>

## Hardware

| Component | Recommended |
|---|---|
| CPU | 16 cores |
| RAM | 32 GB |
| Storage | 500+ GB NVMe |

Initial sync takes roughly 1 day.

## Required configuration

`GENERAL_L1_RPC_URL` **must** point at an **archive** Ethereum L1 RPC. Pruned L1 endpoints panic on startup with `state at block is pruned`. In production this is set per host in the Ansible inventory; for local runs, export it before `./adid up`.

`EXTERNAL_NETWORK_SECRET_KEY` (P2P node identity, `openssl rand -hex 32`) and `BOOT_NODE_URLS` (peer discovery, provided by ADI) are required for the node to sync at all as of v0.20.12. The secret key is unique per node and must be set explicitly in production — this compose does not run ADI's `external-node.sh`, which normally auto-generates one on first start.

## Quick start (local / non-Ansible)

```bash
cp default.env .env
# edit .env: at minimum set GENERAL_L1_RPC_URL to an archive Ethereum RPC
./adid up -d
./adid logs -f adi
# wait for the healthcheck to flip from starting to healthy
./adid check-sync
```

## Operational commands

| Command | Action |
|---|---|
| `./adid up [-d]` | Start the stack |
| `./adid down` | Stop and remove containers (volume preserved) |
| `./adid logs [-f] [service]` | Follow logs (service: `adi`) |
| `./adid version` | Print container image versions |
| `./adid check-sync` | Compare local block height against `https://rpc.adifoundation.ai`, also asserts `eth_syncing=false` |
| `./adid update` | Rebuild env from `default.env` and pull updated images |
| `./adid terminate` | Stop and destroy all data volumes (irreversible) |

## Compose overlays

- `default.env` ships with `COMPOSE_FILE=adi.yml:rpc-shared.yml` so the local dev workflow can hit `http://127.0.0.1:3050`.
- Production (via `cmf-ansible-inventory`) overrides this to `COMPOSE_FILE=adi.yml:ext-network.yml` — no `127.0.0.1` binding; traffic comes in over Traefik vhosts.

## Ports

| Port | Purpose | Exposed by `rpc-shared.yml` | Notes |
|---|---|---|---|
| 3050 | JSON-RPC HTTP + WebSocket (ADI multiplexes both) | yes, `127.0.0.1` | Public over Traefik in prod |
| 3060 | P2P (devp2p), TCP+UDP | no, published directly in `adi.yml` | Must be reachable from the internet — not proxied by Traefik |
| 3071 | Status / health server | no | Host-internal only |
| 3312 | Prometheus `/metrics` | no | Scraped by prom_cluster on the same host |

## Image pinning

All image tags are pinned in `default.env`. Bump deliberately; do not use `latest`. The external node image is currently pinned to `v0.20.12-b1` for mainnet.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Failed to load genesis upgrade transaction: ... state at block is pruned` panic | `GENERAL_L1_RPC_URL` points at a non-archive Ethereum endpoint | Replace with an archive L1 RPC |
| Node never logs `Connected to peer <enode-id>` | Port 3060 not open (firewall/security group), or `BOOT_NODE_URLS`/`EXTERNAL_NETWORK_SECRET_KEY` unset | Check `ufw`/security group for 3060 TCP+UDP; verify both env vars are set |
| Healthcheck stays `starting` for several minutes | Slow disk, insufficient RAM, or L2 replay lag from cold genesis | `./adid logs adi`; if RocksDB is busy persisting blocks, just wait. |
| `./adid logs adi` shows `Connection refused` to `general_l1_rpc_url` | Inventory L1 endpoint down or wrong URL | Verify the L1 host is reachable; check ansible secret rendering |
