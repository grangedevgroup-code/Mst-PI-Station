#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
NOMADNET_SOURCE="${MSTPISTATION_DIR}/SourceDependencies/NomadNet-1.0.1"

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

mkdir -p /var/lib/mstpistation/nomadnet
chown reticulum:reticulum /var/lib/mstpistation/nomadnet 2>/dev/null || true

cat > /etc/systemd/system/mstpistation-nomadnet.service << SERVICE
[Unit]
Description=Mst-PI-Station NomadNet Node
After=reticulum.service
Requires=reticulum.service

[Service]
Type=simple
User=reticulum
Environment=HOME=/var/lib/mstpistation/nomadnet
ExecStart=${VENV}/bin/python3 -m nomadnet --headless --config /var/lib/mstpistation/nomadnet
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mstpistation-nomadnet

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable mstpistation-nomadnet 2>/dev/null || true
systemctl restart mstpistation-nomadnet || true

log "NomadNet installed and running"
