#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
NOMADNET_SOURCE="${AETHERIUM_DIR}/SourceDependencies/NomadNet-1.0.1"

log() { echo "[nomadnet] $*"; }

if [[ -d "${NOMADNET_SOURCE}" ]]; then
    log "Installing NomadNet from local source"
    "${VENV}/bin/pip" install --quiet -e "${NOMADNET_SOURCE}"
else
    log "Installing NomadNet from PyPI"
    "${VENV}/bin/pip" install --quiet nomadnet
fi

"${VENV}/bin/python3" -c "import nomadnet; print('NomadNet', nomadnet.__version__)" 2>/dev/null || \
    log "WARNING: NomadNet verification failed"

mkdir -p /var/lib/aetherium/nomadnet
chown reticulum:reticulum /var/lib/aetherium/nomadnet 2>/dev/null || true

cat > /etc/systemd/system/aetherium-nomadnet.service << SERVICE
[Unit]
Description=Aetherium NomadNet Node
After=reticulum.service
Requires=reticulum.service

[Service]
Type=simple
User=reticulum
Environment=HOME=/var/lib/aetherium/nomadnet
ExecStart=${VENV}/bin/python3 -m nomadnet --headless --config /var/lib/aetherium/nomadnet
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
SyslogIdentifier=aetherium-nomadnet

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable aetherium-nomadnet 2>/dev/null || true
systemctl restart aetherium-nomadnet || true

log "NomadNet installed and running"
