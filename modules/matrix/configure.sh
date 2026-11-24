#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/mstpistation/modules/matrix}"
MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-mstpistation.local}"
MATRIX_ALLOW_REGISTRATION="${MATRIX_ALLOW_REGISTRATION:-true}"

log() { echo "[matrix/configure] $*"; }

# Override server name from mstpistation.yaml
if [[ -f /etc/mstpistation/mstpistation.yaml ]]; then
    MATRIX_SERVER_NAME=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
print(cfg.get('matrix', {}).get('server_name', 'mstpistation.local'))
" 2>/dev/null || echo "mstpistation.local")
    MATRIX_ALLOW_REGISTRATION=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
v = cfg.get('matrix', {}).get('allow_registration', True)
print('true' if v else 'false')
" 2>/dev/null || echo "true")
fi

# Update docker-compose env via override file
cat > "${MODULE_DIR}/docker-compose.override.yml" << OVERRIDE
version: "3.8"
services:
  conduit:
    environment:
      CONDUIT_SERVER_NAME: "${MATRIX_SERVER_NAME}"
      CONDUIT_ALLOW_REGISTRATION: "${MATRIX_ALLOW_REGISTRATION}"
OVERRIDE

docker compose -f "${MODULE_DIR}/docker-compose.yml" \
               -f "${MODULE_DIR}/docker-compose.override.yml" \
               pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" \
               -f "${MODULE_DIR}/docker-compose.override.yml" \
               up -d

sleep 5
if docker ps | grep -q mstpistation-matrix; then
    log "Matrix Conduit running"
    log "Server: ${MATRIX_SERVER_NAME}"
    log "Connect with Element or any Matrix client to http://mstpistation.local:6167"
    log "Registration: ${MATRIX_ALLOW_REGISTRATION}"
else
    log "WARNING: Matrix container not running. Check: docker logs mstpistation-matrix"
fi
