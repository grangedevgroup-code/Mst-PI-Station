#!/usr/bin/env bash
set -euo pipefail

log() { echo "[meshtastic/configure] $*"; }

MESH_PORT=""
if [[ -e /dev/meshtastic0 ]]; then
    MESH_PORT="/dev/meshtastic0"
elif [[ -e /dev/ttyUSB0 ]]; then
    MESH_PORT="/dev/ttyUSB0"
fi

if [[ -z "${MESH_PORT}" ]]; then
    log "No Meshtastic device detected. Bridge will wait for device connection."
fi

[[ -n "${MESH_PORT}" ]] && log "Meshtastic device: ${MESH_PORT}"

# Override service port if detected
if [[ -n "${MESH_PORT}" ]]; then
    mkdir -p /etc/systemd/system/mstpistation-meshtastic.service.d
    cat > /etc/systemd/system/mstpistation-meshtastic.service.d/port.conf << DROP
[Service]
Environment=MESHTASTIC_PORT=${MESH_PORT}
DROP
    systemctl daemon-reload
fi

systemctl enable mstpistation-meshtastic 2>/dev/null || true
systemctl restart mstpistation-meshtastic || true

sleep 2
if systemctl is-active mstpistation-meshtastic &>/dev/null; then
    log "Meshtastic bridge running"
else
    log "Meshtastic bridge starting (waiting for device)"
fi

log "Meshtastic configuration complete"
