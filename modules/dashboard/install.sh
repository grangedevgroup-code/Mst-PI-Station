#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"

log() { echo "[dashboard] $*"; }

# Dashboard deps already in venv (fastapi, uvicorn, etc.)
# Just verify
"${VENV}/bin/python3" -c "import fastapi, uvicorn" 2>/dev/null || \
    "${VENV}/bin/pip" install --quiet fastapi uvicorn[standard] aiofiles python-multipart

# Install systemd service
cat > /etc/systemd/system/mstpistation-dashboard.service << SERVICE
[Unit]
Description=Mst-PI-Station Web Dashboard
After=network.target mstpistation-agent.service

[Service]
Type=simple
WorkingDirectory=${MSTPISTATION_DIR}/dashboard
ExecStart=${VENV}/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --log-level warning
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mstpistation-dashboard

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable mstpistation-dashboard 2>/dev/null || true
systemctl restart mstpistation-dashboard || true

if systemctl is-active mstpistation-dashboard &>/dev/null; then
    log "Dashboard running at http://$(hostname -I | awk '{print $1}'):8080"
else
    log "WARNING: Dashboard failed to start. Check: journalctl -u mstpistation-dashboard"
fi

log "Dashboard installation complete"
