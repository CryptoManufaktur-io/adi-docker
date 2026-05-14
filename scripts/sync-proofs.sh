#!/usr/bin/env sh
# Mirrors the upstream ADI sync-proofs sidecar:
# https://github.com/ADI-Foundation-Labs/ADI-Stack-EN-Setup-script
#
# Bind-mounted into the proof-sync container; runs azcopy in a loop.
set -e

SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
SOURCE="${PROOF_STORAGE_URL:-https://adimainnet.blob.core.windows.net/proofs}"
DESTINATION="${SHARED_PROOF_DIR:-/chain/db/shared}"
DELETE_DESTINATION="${DELETE_DESTINATION:-false}"

log() {
  printf '[%s] [proof-sync] %s\n' "$(date -Iseconds)" "$*"
}

if [ -z "$SOURCE" ]; then
  log "ERROR: PROOF_STORAGE_URL is not set"
  exit 1
fi

log "Starting proof storage sync service"
log "Source: $SOURCE"
log "Destination: $DESTINATION"
log "Sync interval: ${SYNC_INTERVAL}s"
log "Delete destination: $DELETE_DESTINATION"

mkdir -p "$DESTINATION"

while true; do
  log "Starting proof sync..."
  if azcopy sync "$SOURCE" "$DESTINATION" \
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
