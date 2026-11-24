#!/usr/bin/env bash
set -euo pipefail
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[ota] $*"; }

# gnupg for update signature verification
case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gnupg ;;
    fedora) dnf install -y gnupg ;;
    arch)   pacman -S --noconfirm --needed gnupg ;;
esac

"${VENV}/bin/pip" install --quiet gnupg 2>/dev/null || true

mkdir -p /var/lib/mstpistation/ota/incoming \
         /var/lib/mstpistation/ota/applied \
         /var/log/mstpistation/ota

# OTA watcher systemd service
cat > /etc/systemd/system/mstpistation-ota.service << SVC
[Unit]
Description=Mst-PI-Station OTA Update Watcher
After=network.target mstpistation-syncthing.service
Wants=mstpistation-syncthing.service

[Service]
Type=simple
User=root
ExecStart=${VENV}/bin/python3 ${MSTPISTATION_DIR}/modules/ota/watcher.py
Restart=on-failure
RestartSec=30
Environment=MSTPISTATION_DIR=${MSTPISTATION_DIR}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
log "OTA update watcher installed"
log "Drop update bundles (*.aeth-update) into /var/lib/mstpistation/ota/incoming/"
