# ADI Docker

Docker Compose deployment for an ADI mainnet external RPC node.

This is ADI Docker v0.1.0

ADI is a zkSync-based L2. The external node is read-only: it replays L2 blocks locally, serves JSON-RPC, and continuously syncs proving artifacts from ADI-hosted Azure Blob storage.

## Quick Start

```bash
git clone https://github.com/CryptoManufaktur-io/adi-docker.git
cd adi-docker
cp default.env .env
```

Edit `.env` and set `GENERAL_L1_RPC_URL` to an archive Ethereum L1 RPC endpoint. Pruned L1 RPCs can panic at startup with `state at block is pruned`.

```bash
./adid up
./adid check-sync
```

## Requirements

- Docker Engine 23+ with Compose V2
- Archive Ethereum L1 RPC endpoint
- Recommended host sizing: 16 CPU cores, 32 GB RAM, 500+ GB NVMe

## Network

| Field | Value |
| --- | --- |
| Network | ADI mainnet |
| Chain ID | `36900` / `0x9024` |
| Public RPC | `https://rpc.adifoundation.ai` |
| Explorer | `https://explorer.adifoundation.ai` |
| Local JSON-RPC | `127.0.0.1:3050` |
| Status port | `127.0.0.1:3071` |
| Metrics port | `127.0.0.1:3312` |

ADI uses port `3050` for both HTTP and WebSocket JSON-RPC.

## Configuration

Key variables in `.env`:

| Variable | Description | Default |
| --- | --- | --- |
| `COMPOSE_FILE` | Compose files to use | `adi.yml:rpc-shared.yml` |
| `PROJECT_NAME` | Container name prefix | `adi` |
| `NODE_DOCKER_REPO` | ADI external node image repo | `harbor.sre.ideasoft.io/adi-chain/external-node` |
| `NODE_DOCKER_TAG` | ADI external node image tag | `v0.13.0-b1` |
| `AZCOPY_DOCKER_REPO` | Proof-sync image repo | `peterdavehello/azcopy` |
| `AZCOPY_DOCKER_TAG` | Proof-sync image tag | `10.27.1` |
| `DATA_DIR` | Node/proof data directory | `./mainnet_data` |
| `GENERAL_L1_RPC_URL` | Required archive Ethereum L1 RPC | empty |
| `PUBLIC_RPC` | Reference RPC for sync checks | `https://rpc.adifoundation.ai` |
| `RPC_HOST` / `WS_HOST` | Traefik route hostnames | `adi` / `adiws` |

For production behind Traefik, use:

```bash
COMPOSE_FILE=adi.yml:rpc-shared.yml:ext-network.yml
DOMAIN=cryptomanufaktur.net
RPC_HOST=adi-a
WS_HOST=adiws-a
RPC_LB=adi-lb
WS_LB=adiws-lb
```

## Commands

| Command | Description |
| --- | --- |
| `./adid up` | Prepare data directories and start the node |
| `./adid down` | Stop the node |
| `./adid restart` | Restart the node |
| `./adid logs -f` | Follow logs |
| `./adid check-sync` | Compare local latest block to the public ADI RPC |
| `./adid version` | Show configured image versions |
| `./adid cmd <args>` | Run a raw Docker Compose command |

`./adid check-sync` defaults to `http://127.0.0.1:3050` and `https://rpc.adifoundation.ai`, so it works when `rpc-shared.yml` is enabled.

## Services

- `adi`: ADI external node, serving JSON-RPC on port `3050`.
- `proof-sync`: `azcopy` sidecar that keeps `/chain/db/shared` synchronized from ADI Azure Blob proof storage.

## Sources

- ADI setup guide: `https://github.com/smartcontractkit/node-ops-wiki/blob/main/docs/Blockchains/ADI_Setup_Guide.md`
- Upstream setup repo: `https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script`
- ADI docs: `https://docs.adi.foundation/`
