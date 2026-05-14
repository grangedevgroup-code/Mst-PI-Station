#!/usr/bin/env bash
set -euo pipefail
AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[ota] $*"; }

# gnupg for update signature verification
case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gnupg ;;
    fedora) dnf install -y gnupg ;;
    arch)   pacman -S --noconfirm --needed gnupg ;;
esac

"${VENV}/bin/pip" install --quiet gnupg 2>/dev/null || true

mkdir -p /var/lib/aetherium/ota/incoming \
         /var/lib/aetherium/ota/applied \
         /var/log/aetherium/ota

# OTA watcher systemd service
cat > /etc/systemd/system/aetherium-ota.service << SVC
[Unit]
Description=Aetherium OTA Update Watcher
After=network.target aetherium-syncthing.service
Wants=aetherium-syncthing.service

[Service]
Type=simple
User=root
ExecStart=${VENV}/bin/python3 ${AETHERIUM_DIR}/modules/ota/watcher.py
Restart=on-failure
RestartSec=30
Environment=AETHERIUM_DIR=${AETHERIUM_DIR}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
log "OTA update watcher installed"
log "Drop update bundles (*.aeth-update) into /var/lib/aetherium/ota/incoming/"
