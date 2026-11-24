#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"

log() { echo "[meshtastic] $*"; }

# Install Meshtastic Python library and CLI
"${VENV}/bin/pip" install --quiet meshtastic 2>/dev/null || true

# Install additional deps for the LXMF bridge
"${VENV}/bin/pip" install --quiet pyserial 2>/dev/null || true

# udev rules for Meshtastic devices
cat > /etc/udev/rules.d/99-mstpistation-meshtastic.rules << 'UDEV'
# Meshtastic device rules

# CP2102 (TTGO T-Beam, Heltec, WisMesh Pocket)
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", \
    SYMLINK+="meshtastic0", MODE="0660", GROUP="dialout"

# CH340 (common clone boards)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", \
    SYMLINK+="meshtastic0", MODE="0660", GROUP="dialout"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", \
    SYMLINK+="meshtastic0", MODE="0660", GROUP="dialout"

# RAK WisMesh (nRF52840 USB)
SUBSYSTEM=="tty", ATTRS{idVendor}=="239a", ATTRS{idProduct}=="0029", \
    SYMLINK+="meshtastic0", MODE="0660", GROUP="dialout"

# LILYGO T-Deck
SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", \
    SYMLINK+="meshtastic0", MODE="0660", GROUP="dialout"
UDEV

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# Add reticulum user to dialout
usermod -aG dialout reticulum 2>/dev/null || true

mkdir -p /var/lib/mstpistation/meshtastic
chown reticulum:reticulum /var/lib/mstpistation/meshtastic

# Install the bridge service
cat > /etc/systemd/system/mstpistation-meshtastic.service << SVC
[Unit]
Description=Mst-PI-Station Meshtastic Bridge
After=reticulum.service mstpistation-lxmf.service
Requires=reticulum.service

[Service]
Type=simple
User=reticulum
ExecStart=${VENV}/bin/python3 ${MSTPISTATION_DIR}/modules/meshtastic/bridge.py
Restart=on-failure
RestartSec=20
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mstpistation-meshtastic

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
log "Meshtastic module installed"

if ls /dev/meshtastic* &>/dev/null 2>&1; then
    log "Meshtastic device found: $(ls /dev/meshtastic*)"
else
    log "No Meshtastic device detected. Connect device and run: mstpistation module enable meshtastic"
fi
