#!/usr/bin/env bash
set -euo pipefail

log() { echo "[sms-bridge/configure] $*"; }

# Check if a modem is present
MODEM=$(mmcli -L 2>/dev/null | grep -c "Modem" || echo "0")
if [[ "${MODEM}" -eq 0 ]]; then
    log "WARNING: No LTE modem detected — SMS bridge will wait for modem"
fi

mkdir -p /var/log/aetherium/sms-bridge /var/lib/aetherium
chown -R aetherium:aetherium /var/log/aetherium/sms-bridge 2>/dev/null || true

systemctl enable aetherium-sms-bridge 2>/dev/null || true
systemctl restart aetherium-sms-bridge || true

sleep 2
if systemctl is-active aetherium-sms-bridge &>/dev/null; then
    log "SMS bridge running"
    log "Incoming SMS forwarded to LXMF mesh"
    log "Send SMS via LXMF: '+15551234567 Your message'"
    log "Message log: /var/log/aetherium/sms-bridge/messages.jsonl"
else
    log "WARNING: SMS bridge not running — check: journalctl -u aetherium-sms-bridge"
fi
