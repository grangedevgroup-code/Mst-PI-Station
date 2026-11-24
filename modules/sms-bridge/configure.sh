#!/usr/bin/env bash
set -euo pipefail

log() { echo "[sms-bridge/configure] $*"; }

# Check if a modem is present
MODEM=$(mmcli -L 2>/dev/null | grep -c "Modem" || echo "0")
if [[ "${MODEM}" -eq 0 ]]; then
    log "WARNING: No LTE modem detected — SMS bridge will wait for modem"
fi

mkdir -p /var/log/mstpistation/sms-bridge /var/lib/mstpistation
chown -R mstpistation:mstpistation /var/log/mstpistation/sms-bridge 2>/dev/null || true

systemctl enable mstpistation-sms-bridge 2>/dev/null || true
systemctl restart mstpistation-sms-bridge || true

sleep 2
if systemctl is-active mstpistation-sms-bridge &>/dev/null; then
    log "SMS bridge running"
    log "Incoming SMS forwarded to LXMF mesh"
    log "Send SMS via LXMF: '+15551234567 Your message'"
    log "Message log: /var/log/mstpistation/sms-bridge/messages.jsonl"
else
    log "WARNING: SMS bridge not running — check: journalctl -u mstpistation-sms-bridge"
fi
