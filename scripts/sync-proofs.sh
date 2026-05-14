#!/usr/bin/env sh
# Combined data-dir bootstrap + azcopy sync sidecar for the ADI external node.
# Runs as root in the proof-sync container; the ADI service depends on this
# container being up before it starts.
#
# Responsibilities:
#   1. Create the chain data dirs the ADI node will write into and make them
#      world-writable (the node container may run as a non-root uid).
#   2. Loop forever, calling `azcopy sync` against the Azure Blob proof store
#      every SYNC_INTERVAL seconds.
#
# Upstream reference:
#   https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script
set -e

CHAIN_DATA_DIR="${CHAIN_DATA_DIR:-/chain}"
SHARED_PROOF_DIR="${SHARED_PROOF_DIR:-$CHAIN_DATA_DIR/db/shared}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
SOURCE="${PROOF_STORAGE_URL:-https://adimainnet.blob.core.windows.net/proofs}"
DELETE_DESTINATION="${DELETE_DESTINATION:-false}"

log() {
  printf '[%s] [proof-sync] %s\n' "$(date -Iseconds)" "$*"
}

if [ -z "$SOURCE" ]; then
  log "ERROR: PROOF_STORAGE_URL is not set"
  exit 1
fi

log "Bootstrapping chain data dirs under $CHAIN_DATA_DIR"
mkdir -p "$CHAIN_DATA_DIR/db/node1/block_dumps" "$SHARED_PROOF_DIR"
chmod -R 0777 "$CHAIN_DATA_DIR"

log "Starting proof storage sync service"
log "Source:             $SOURCE"
log "Destination:        $SHARED_PROOF_DIR"
log "Sync interval:      ${SYNC_INTERVAL}s"
log "Delete destination: $DELETE_DESTINATION"

while true; do
  log "Starting proof sync..."
  if azcopy sync "$SOURCE" "$SHARED_PROOF_DIR" \
    --recursive \
    --delete-destination="$DELETE_DESTINATION" \
    --log-level=INFO; then
    log "Proof sync completed successfully"
  else
    exit_code=$?
    log "ERROR: Proof sync failed with exit code $exit_code"
  fi
  log "Next sync in ${SYNC_INTERVAL}s"
  sleep "$SYNC_INTERVAL"
done
