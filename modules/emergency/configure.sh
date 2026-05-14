#!/usr/bin/env bash
set -euo pipefail

log() { echo "[emergency/configure] $*"; }

mkdir -p /var/lib/aetherium /var/log/aetherium/emergency
chown -R aetherium:aetherium /var/log/aetherium/emergency 2>/dev/null || true

systemctl restart aetherium-emergency || true
sleep 2
if systemctl is-active aetherium-emergency &>/dev/null; then
    log "Emergency listener active"
    log "Send alert: aetherium emergency send 'message'"
    log "Alert log: /var/log/aetherium/emergency/alerts.log"
else
    log "WARNING: Emergency listener not running — check: journalctl -u aetherium-emergency"
fi
