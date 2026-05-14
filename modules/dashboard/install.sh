#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"

log() { echo "[dashboard] $*"; }

# Dashboard deps already in venv (fastapi, uvicorn, etc.)
# Just verify
"${VENV}/bin/python3" -c "import fastapi, uvicorn" 2>/dev/null || \
    "${VENV}/bin/pip" install --quiet fastapi uvicorn[standard] aiofiles python-multipart

# Install systemd service
cat > /etc/systemd/system/aetherium-dashboard.service << SERVICE
[Unit]
Description=Aetherium Web Dashboard
After=network.target aetherium-agent.service

[Service]
Type=simple
WorkingDirectory=${AETHERIUM_DIR}/dashboard
ExecStart=${VENV}/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --log-level warning
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=aetherium-dashboard

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable aetherium-dashboard 2>/dev/null || true
systemctl restart aetherium-dashboard || true

if systemctl is-active aetherium-dashboard &>/dev/null; then
    log "Dashboard running at http://$(hostname -I | awk '{print $1}'):8080"
else
    log "WARNING: Dashboard failed to start. Check: journalctl -u aetherium-dashboard"
fi

log "Dashboard installation complete"
