#!/usr/bin/env bash
set -euo pipefail

log() { echo "[emergency/configure] $*"; }

mkdir -p /var/lib/mstpistation /var/log/mstpistation/emergency
chown -R mstpistation:mstpistation /var/log/mstpistation/emergency 2>/dev/null || true

systemctl restart mstpistation-emergency || true
sleep 2
if systemctl is-active mstpistation-emergency &>/dev/null; then
    log "Emergency listener active"
    log "Send alert: mstpistation emergency send 'message'"
    log "Alert log: /var/log/mstpistation/emergency/alerts.log"
else
    log "WARNING: Emergency listener not running — check: journalctl -u mstpistation-emergency"
fi
