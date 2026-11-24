#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"

log() { echo "[sms-bridge] $*"; }

# ModemManager + python bindings
case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            modemmanager libmodem-manager-qt-dev python3-dbus 2>/dev/null || true
        ;;
    fedora)
        dnf install -y ModemManager python3-dbus 2>/dev/null || true
        ;;
    arch)
        pacman -S --noconfirm --needed modemmanager python-dbus 2>/dev/null || true
        ;;
esac

# Python dbus bindings in venv
"${VENV}/bin/pip" install --quiet dbus-python 2>/dev/null || \
    log "WARNING: dbus-python install failed — may need system package"

systemctl enable ModemManager 2>/dev/null || true
systemctl start ModemManager || true

mkdir -p /var/lib/mstpistation/sms /var/log/mstpistation/sms-bridge

# SMS bridge systemd service
cat > /etc/systemd/system/mstpistation-sms-bridge.service << SVC
[Unit]
Description=Mst-PI-Station SMS ↔ LXMF Bridge
After=network.target ModemManager.service reticulum.service mstpistation-lxmf.service
Wants=ModemManager.service

[Service]
Type=simple
User=mstpistation
ExecStart=${VENV}/bin/python3 ${MSTPISTATION_DIR}/modules/sms-bridge/bridge.py
Restart=on-failure
RestartSec=15
Environment=MSTPISTATION_DIR=${MSTPISTATION_DIR}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
log "SMS bridge installed"
