#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/mstpistation/modules/gitea}"
NODE_NAME="${NODE_NAME:-mstpistation-node}"

log() { echo "[gitea/configure] $*"; }

docker compose -f "${MODULE_DIR}/docker-compose.yml" pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" up -d

sleep 5
if docker ps | grep -q mstpistation-gitea; then
    log "Gitea running — web UI at http://mstpistation.local:3000"
    log "First visit: complete the admin setup wizard"
    log "SSH clone port: 2222"
else
    log "WARNING: Gitea container not running. Check: docker logs mstpistation-gitea"
fi
