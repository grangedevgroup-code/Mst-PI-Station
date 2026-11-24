#!/usr/bin/env bash
set -euo pipefail
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"

log() { echo "[emergency] $*"; }

# No extra deps — uses LXMF which is already installed
mkdir -p /etc/mstpistation/emergency /var/log/mstpistation/emergency

# Install broadcast daemon
install -m 755 "${MSTPISTATION_DIR}/modules/emergency/broadcast.py" \
    "${MSTPISTATION_DIR}/bin/emergency-broadcast" 2>/dev/null || \
cp "${MSTPISTATION_DIR}/modules/emergency/broadcast.py" \
    "${MSTPISTATION_DIR}/bin/emergency-broadcast" && \
chmod +x "${MSTPISTATION_DIR}/bin/emergency-broadcast"

# Systemd listener service (receives alerts and logs/displays them)
cat > /etc/systemd/system/mstpistation-emergency.service << SVC
[Unit]
Description=Mst-PI-Station Emergency Alert Listener
After=network.target reticulum.service mstpistation-lxmf.service
Requires=reticulum.service

[Service]
Type=simple
User=mstpistation
ExecStart=${VENV}/bin/python3 ${MSTPISTATION_DIR}/modules/emergency/listener.py
Restart=on-failure
RestartSec=5
Environment=MSTPISTATION_DIR=${MSTPISTATION_DIR}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable mstpistation-emergency 2>/dev/null || true
log "Emergency alert module installed"
log "Send alert: mstpistation emergency send 'your message'"
