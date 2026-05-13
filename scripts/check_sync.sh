#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: check_sync.sh [options]

Options:
  --container NAME         Docker container name or ID to run curl within
  --compose-service NAME   Docker Compose service name to resolve to a container
  --local-rpc URL          Local RPC URL (default: http://127.0.0.1:3050)
  --public-rpc URL         Public/reference RPC URL (default: https://rpc.adifoundation.ai)
  --block-lag N            Acceptable lag in blocks (default: 5)
  --no-install             Do not install curl/jq inside the container
  --env-file PATH          Path to env file to load
  -h, --help               Show this help

Exit Codes:
  0 - Synced
  1 - Syncing
  2 - Error or diverged
USAGE
}

ENV_FILE="${ENV_FILE:-}"
CONTAINER="${CONTAINER:-}"
DOCKER_SERVICE="${DOCKER_SERVICE:-}"
LOCAL_RPC="${LOCAL_RPC:-}"
PUBLIC_RPC="${PUBLIC_RPC:-}"
BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-5}"
INSTALL_TOOLS="${INSTALL_TOOLS:-1}"
EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-0x9024}"

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

fail() {
  echo "❌ error: $*"
  echo
  echo "❌ Final status: error"
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --container)
        [[ $# -ge 2 ]] || fail "missing value for --container"
        CONTAINER="$2"
        shift 2
        ;;
      --compose-service)
        [[ $# -ge 2 ]] || fail "missing value for --compose-service"
        DOCKER_SERVICE="$2"
        shift 2
        ;;
      --local-rpc)
        [[ $# -ge 2 ]] || fail "missing value for --local-rpc"
        LOCAL_RPC="$2"
        shift 2
        ;;
      --public-rpc)
        [[ $# -ge 2 ]] || fail "missing value for --public-rpc"
        PUBLIC_RPC="$2"
        shift 2
        ;;
      --block-lag)
        [[ $# -ge 2 ]] || fail "missing value for --block-lag"
        BLOCK_LAG_THRESHOLD="$2"
        shift 2
        ;;
      --env-file)
        [[ $# -ge 2 ]] || fail "missing value for --env-file"
        ENV_FILE="$2"
        shift 2
        ;;
      --no-install)
        INSTALL_TOOLS=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done
}

resolve_defaults() {
  if [[ -n "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
  elif [[ -f .env ]]; then
    load_env_file .env
  fi

  LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:${RPC_PORT:-3050}}"
  PUBLIC_RPC="${PUBLIC_RPC:-${PUBLIC_RPC_URL:-${PUBLIC_RPC_DEFAULT:-https://rpc.adifoundation.ai}}}"
  EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-0x9024}"
}

resolve_container() {
  if [[ -n "$CONTAINER" || -z "$DOCKER_SERVICE" ]]; then
    return 0
  fi
  command -v docker >/dev/null 2>&1 || fail "docker not found; cannot resolve --compose-service"
  if docker compose version >/dev/null 2>&1; then
    CONTAINER="$(docker compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    CONTAINER="$(docker-compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  else
    fail "docker compose not available; cannot resolve --compose-service"
  fi
  [[ -n "$CONTAINER" ]] || fail "no running container found for service: $DOCKER_SERVICE"
}

ensure_tools() {
  if [[ -n "$CONTAINER" ]]; then
    echo "⏳ Checking tools inside container"
    if docker exec "$CONTAINER" sh -c 'command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1'; then
      echo "✅ Tools available in container"
      echo
      return 0
    fi
    [[ "$INSTALL_TOOLS" == "1" ]] || fail "curl/jq missing inside container"
    docker exec -u root "$CONTAINER" sh -c '
      set -e
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null
        apt-get install -y curl jq ca-certificates >/dev/null
      elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl jq ca-certificates >/dev/null
      else
        echo "unsupported container base image"
        exit 1
      fi
    ' || fail "failed to install curl/jq inside container"
    echo "✅ Tools available in container"
    echo
    return 0
  fi

  command -v curl >/dev/null 2>&1 || fail "curl not found"
  command -v jq >/dev/null 2>&1 || fail "jq not found"
}

rpc_post() {
  local url="$1"
  local data="$2"
  if [[ -n "$CONTAINER" ]]; then
    docker exec "$CONTAINER" curl -sS --fail --connect-timeout 5 --max-time 20 \
      -X POST -H "Content-Type: application/json" -d "$data" "$url"
  else
    curl -sS --fail --connect-timeout 5 --max-time 20 \
      -X POST -H "Content-Type: application/json" -d "$data" "$url"
  fi
}

jq_get() {
  jq -r "$1"
}

hex_to_dec() {
  local hex="${1#0x}"
  printf '%d' "$((16#$hex))"
}

get_latest_block() {
  local rpc="$1"
  local label="$2"
  local response number hash
  response="$(rpc_post "$rpc" '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}')" ||
    fail "$label RPC unreachable ($rpc)"
  number="$(echo "$response" | jq_get '.result.number // empty')" ||
    fail "failed to parse $label latest block"
  hash="$(echo "$response" | jq_get '.result.hash // empty')" ||
    fail "failed to parse $label latest block"
  [[ -n "$number" && "$number" != "null" ]] || fail "$label RPC returned no latest block number"
  [[ -n "$hash" && "$hash" != "null" ]] || fail "$label RPC returned no latest block hash"
  printf '%s\t%s\n' "$(hex_to_dec "$number")" "$hash"
}

check_chain_id() {
  local rpc="$1"
  local label="$2"
  local response chain_id
  response="$(rpc_post "$rpc" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')" ||
    fail "$label RPC unreachable ($rpc)"
  chain_id="$(echo "$response" | jq_get '.result // empty')" ||
    fail "failed to parse $label chain ID"
  [[ "$chain_id" == "$EXPECTED_CHAIN_ID" ]] ||
    fail "$label chain ID $chain_id does not match expected $EXPECTED_CHAIN_ID"
}

node_reports_syncing() {
  local response syncing
  response="$(rpc_post "$LOCAL_RPC" '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')" || return 1
  syncing="$(echo "$response" | jq_get '.result')" || return 1
  [[ "$syncing" != "false" && "$syncing" != "null" ]]
}

main() {
  parse_args "$@"
  resolve_defaults
  resolve_container
  ensure_tools

  check_chain_id "$LOCAL_RPC" "local"
  check_chain_id "$PUBLIC_RPC" "public"

  echo "⏳ Latest block comparison"
  local local_info public_info local_height local_hash public_height public_hash lag abs_lag direction
  local_info="$(get_latest_block "$LOCAL_RPC" "local")"
  public_info="$(get_latest_block "$PUBLIC_RPC" "public")"
  local_height="${local_info%%$'\t'*}"
  local_hash="${local_info#*$'\t'}"
  public_height="${public_info%%$'\t'*}"
  public_hash="${public_info#*$'\t'}"

  lag=$((public_height - local_height))
  abs_lag="${lag#-}"
  if (( lag > 0 )); then
    direction="local behind"
  elif (( lag < 0 )); then
    direction="local ahead"
  else
    direction="in sync"
  fi

  printf 'Local latest:  %s %s\n' "$local_height" "$local_hash"
  printf 'Public latest: %s %s\n' "$public_height" "$public_hash"
  printf 'Lag:         %s blocks (threshold: %s) (%s)\n' "$abs_lag" "$BLOCK_LAG_THRESHOLD" "$direction"
  echo

  if (( lag == 0 )) && [[ "$local_hash" != "$public_hash" ]]; then
    echo "❌ Final status: error"
    exit 2
  fi

  if node_reports_syncing || (( abs_lag > BLOCK_LAG_THRESHOLD && lag > 0 )); then
    echo "⏳ Final status: syncing"
    exit 1
  fi

  echo "✅ Final status: in sync"
}

main "$@"
