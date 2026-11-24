#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/mstpistation/modules/mumble}"
NODE_NAME="${NODE_NAME:-Mst-PI-Station}"

log() { echo "[mumble/configure] $*"; }

docker compose -f "${MODULE_DIR}/docker-compose.yml" pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" up -d

sleep 3
if docker ps | grep -q mstpistation-mumble; then
    log "Mumble voice server running on port 64738"
    log "Connect with Mumble client: mstpistation.local:64738"
else
    log "WARNING: Mumble not running. Check: docker logs mstpistation-mumble"
fi
