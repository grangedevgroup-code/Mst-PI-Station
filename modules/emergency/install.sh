#!/usr/bin/env bash
set -euo pipefail
AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"

log() { echo "[emergency] $*"; }

# No extra deps — uses LXMF which is already installed
mkdir -p /etc/aetherium/emergency /var/log/aetherium/emergency

# Install broadcast daemon
install -m 755 "${AETHERIUM_DIR}/modules/emergency/broadcast.py" \
    "${AETHERIUM_DIR}/bin/emergency-broadcast" 2>/dev/null || \
cp "${AETHERIUM_DIR}/modules/emergency/broadcast.py" \
    "${AETHERIUM_DIR}/bin/emergency-broadcast" && \
chmod +x "${AETHERIUM_DIR}/bin/emergency-broadcast"

# Systemd listener service (receives alerts and logs/displays them)
cat > /etc/systemd/system/aetherium-emergency.service << SVC
[Unit]
Description=Aetherium Emergency Alert Listener
After=network.target reticulum.service aetherium-lxmf.service
Requires=reticulum.service

[Service]
Type=simple
User=aetherium
ExecStart=${VENV}/bin/python3 ${AETHERIUM_DIR}/modules/emergency/listener.py
Restart=on-failure
RestartSec=5
Environment=AETHERIUM_DIR=${AETHERIUM_DIR}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable aetherium-emergency 2>/dev/null || true
log "Emergency alert module installed"
log "Send alert: aetherium emergency send 'your message'"
