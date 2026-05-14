#!/usr/bin/env bash
# =============================================================================
# check_sync.sh — ADI external node sync check
# =============================================================================
# ADI is a zkSync-based L2. The external node serves a standard JSON-RPC
# interface, so we use eth_blockNumber against the local node and a public
# reference RPC to compute lag.
#
# Exit codes:
#   0 - Synced (lag within threshold)
#   1 - Syncing (behind public)
#   3 - Local RPC error
#   4 - Public RPC error
#   5 - Configuration error
#   6 - Missing dependencies (curl / jq)
#   7 - Container resolution error
# =============================================================================
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: check_sync.sh [options]

Options:
  --container NAME         Run curl/jq inside this Docker container
  --compose-service NAME   Resolve container by docker compose service name
  --local-rpc URL          Local JSON-RPC URL (default: http://127.0.0.1:${RPC_PORT:-3050})
  --public-rpc URL         Public reference RPC URL (default: $MAIN_RPC_URL or https://rpc.adifoundation.ai)
  --block-lag N            Acceptable lag in blocks (default: 5)
  --no-install             Do not install curl/jq inside the container
  --env-file PATH          Path to env file to load (default: ./.env)
  -h, --help               Show this help
USAGE
}

ENV_FILE="${ENV_FILE:-}"
CONTAINER="${CONTAINER:-}"
DOCKER_SERVICE="${DOCKER_SERVICE:-adi}"
LOCAL_RPC="${LOCAL_RPC:-}"
PUBLIC_RPC="${PUBLIC_RPC:-}"
BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-5}"
INSTALL_TOOLS="${INSTALL_TOOLS:-1}"

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line#export }"
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      local key="${line%%=*}"
      local val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"
      if [[ "$val" =~ ^\".*\"$ ]]; then
        val="${val:1:-1}"
      elif [[ "$val" =~ ^\'.*\'$ ]]; then
        val="${val:1:-1}"
      fi
      export "${key}=${val}"
    fi
  done < "$file"
}

resolve_container() {
  if [[ -n "$CONTAINER" || -z "$DOCKER_SERVICE" ]]; then
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found; cannot resolve --compose-service $DOCKER_SERVICE"
    exit 7
  fi
  if docker compose version >/dev/null 2>&1; then
    CONTAINER="$(docker compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    CONTAINER="$(docker-compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  else
    echo "docker compose not available; cannot resolve --compose-service $DOCKER_SERVICE"
    exit 7
  fi
  if [[ -z "$CONTAINER" ]]; then
    echo "No running container found for service: $DOCKER_SERVICE"
    exit 7
  fi
}

http_post() {
  local url="$1"
  local data="$2"
  if [[ -n "$CONTAINER" ]]; then
    docker exec "$CONTAINER" curl -sS -X POST -H "Content-Type: application/json" -d "$data" "$url"
  else
    curl -sS -X POST -H "Content-Type: application/json" -d "$data" "$url"
  fi
}

jq_eval() {
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" jq -r "$1"
  else
    jq -r "$1"
  fi
}

install_tools_in_container() {
  if [[ -z "$CONTAINER" || "$INSTALL_TOOLS" != "1" ]]; then
    return 0
  fi
  docker exec -u root "$CONTAINER" sh -c '
    set -e
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      exit 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y >/dev/null
      apt-get install -y curl jq ca-certificates >/dev/null
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache curl jq ca-certificates >/dev/null
    else
      echo "Unsupported base image. No apt-get or apk found." >&2
      exit 1
    fi
  '
}

check_adi_sync() {
  echo "==> Checking ADI external node sync status"

  # 1. eth_syncing — node's self-reported sync state.
  # ADI's zkSync-style external node can report a stale block height close
  # to head while still replaying L2 blocks. eth_syncing returns an object
  # while catching up, false once caught up. Treat this as the authoritative
  # syncing signal; eth_blockNumber lag is then a sanity check.
  local syncing_resp
  if ! syncing_resp=$(http_post "$LOCAL_RPC" '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'); then
    echo "Failed to call eth_syncing on local node"
    exit 3
  fi
  local syncing_result
  syncing_result=$(printf '%s' "$syncing_resp" | jq_eval '.result')
  if [[ -z "$syncing_result" || "$syncing_result" == "null" ]]; then
    echo "Local node returned invalid eth_syncing response: $syncing_resp"
    exit 3
  fi
  if [[ "$syncing_result" != "false" ]]; then
    echo "Local node reports eth_syncing=true: $syncing_result"
    exit 1
  fi

  # 2. eth_blockNumber lag check against the public ADI RPC.
  local local_resp
  if ! local_resp=$(http_post "$LOCAL_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'); then
    echo "Failed to call eth_blockNumber on local node"
    exit 3
  fi
  local local_hex
  local_hex=$(printf '%s' "$local_resp" | jq_eval '.result')
  if [[ -z "$local_hex" || "$local_hex" == "null" ]]; then
    echo "Failed to read local block number; response: $local_resp"
    exit 3
  fi

  local public_resp
  if ! public_resp=$(http_post "$PUBLIC_RPC" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'); then
    echo "Failed to call eth_blockNumber on public RPC"
    exit 4
  fi
  local public_hex
  public_hex=$(printf '%s' "$public_resp" | jq_eval '.result')
  if [[ -z "$public_hex" || "$public_hex" == "null" ]]; then
    echo "Failed to read public block number; response: $public_resp"
    exit 4
  fi

  local local_block=$((16#${local_hex#0x}))
  local public_block=$((16#${public_hex#0x}))
  local lag=$((public_block - local_block))

  echo "Local block:  $local_block"
  echo "Public block: $public_block"
  echo "Lag:          $lag blocks (threshold: $BLOCK_LAG_THRESHOLD)"

  if (( lag <= BLOCK_LAG_THRESHOLD && lag >= -BLOCK_LAG_THRESHOLD )); then
    echo "Node is synced"
    exit 0
  elif (( lag > BLOCK_LAG_THRESHOLD )); then
    echo "Node is syncing (behind by $lag blocks)"
    exit 1
  else
    echo "Node is ahead of public RPC (public may be lagging)"
    exit 0
  fi
}

args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "--env-file" ]]; then
    ENV_FILE="${args[$((i+1))]:-}"
  fi
done

if [[ -n "${ENV_FILE:-}" ]]; then
  load_env_file "$ENV_FILE"
elif [[ -f ".env" ]]; then
  load_env_file ".env"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container|--compose-service|--local-rpc|--public-rpc|--block-lag|--env-file)
      if [[ $# -lt 2 ]]; then echo "Error: $1 requires a value"; exit 5; fi
      ;;&
    --container) CONTAINER="$2"; shift 2 ;;
    --compose-service) DOCKER_SERVICE="$2"; shift 2 ;;
    --local-rpc) LOCAL_RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --block-lag) BLOCK_LAG_THRESHOLD="$2"; shift 2 ;;
    --no-install) INSTALL_TOOLS="0"; shift ;;
    --env-file) shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 5 ;;
  esac
done

LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:${RPC_PORT:-3050}}"
PUBLIC_RPC="${PUBLIC_RPC:-${MAIN_RPC_URL:-https://rpc.adifoundation.ai}}"
# Back-compat: --public-rpc / PUBLIC_RPC are accepted for explicit overrides,
# but default.env only ships MAIN_RPC_URL since the two values are always the
# same for ADI (the public RPC is the main node).

resolve_container

if [[ -z "$CONTAINER" ]]; then
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "curl and jq are required on the host when no --container is set."
    exit 6
  fi
else
  install_tools_in_container
fi

check_adi_sync
