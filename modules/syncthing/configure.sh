#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/aetherium/modules/syncthing}"
NODE_NAME="${NODE_NAME:-aetherium-node}"

log() { echo "[syncthing/configure] $*"; }

# Inject node name into compose env
export NODE_NAME="${NODE_NAME}"

docker compose -f "${MODULE_DIR}/docker-compose.yml" pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" up -d

sleep 5
if docker ps | grep -q aetherium-syncthing; then
    log "Syncthing running — web UI at http://aetherium.local:8384"
    log "No password set by default. Set one in Settings → GUI in the web UI."
else
    log "WARNING: Syncthing container not running. Check: docker logs aetherium-syncthing"
fi

log "Syncthing configuration complete"
