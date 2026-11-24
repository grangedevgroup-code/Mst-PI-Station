#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
OTA_SIGNING_KEY="${OTA_SIGNING_KEY:-}"

log() { echo "[ota/configure] $*"; }

mkdir -p /etc/mstpistation/ota /var/lib/mstpistation/ota/incoming /var/lib/mstpistation/ota/applied
mkdir -p /var/log/mstpistation/ota

# Generate or import signing key
if [[ -n "${OTA_SIGNING_KEY}" ]] && [[ -f "${OTA_SIGNING_KEY}" ]]; then
    gpg --no-default-keyring --keyring /etc/mstpistation/ota/trusted-keys.gpg \
        --import "${OTA_SIGNING_KEY}" 2>/dev/null || true
    log "OTA signing key imported"
else
    log "No OTA signing key configured — signature verification disabled"
    log "Set ota.signing_key in mstpistation.yaml to enable verified updates"
fi

# Set up Syncthing shared folder for OTA bundles (if Syncthing is running)
if command -v curl &>/dev/null && curl -sf http://localhost:8384/rest/system/ping &>/dev/null; then
    log "Syncthing detected — add shared folder 'mstpistation-ota' pointing to /var/lib/mstpistation/ota/incoming"
    log "Share this folder across your mesh nodes to distribute updates"
fi

systemctl enable mstpistation-ota 2>/dev/null || true
systemctl restart mstpistation-ota || true

sleep 2
if systemctl is-active mstpistation-ota &>/dev/null; then
    log "OTA watcher running"
    log "Drop *.aeth-update bundles into: /var/lib/mstpistation/ota/incoming/"
    log "Or share via Syncthing for automatic mesh distribution"
else
    log "WARNING: OTA watcher not running — check: journalctl -u mstpistation-ota"
fi
