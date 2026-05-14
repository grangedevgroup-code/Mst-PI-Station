#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/aetherium/modules/monitoring}"
AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"

log() { echo "[monitoring/configure] $*"; }

mkdir -p /var/lib/aetherium/prometheus /var/lib/aetherium/grafana
chmod 777 /var/lib/aetherium/grafana  # Grafana writes as its own uid

# Deploy Aetherium exporter systemd service
cat > /etc/systemd/system/aetherium-exporter.service << SVC
[Unit]
Description=Aetherium Custom Metrics Exporter
After=network.target

[Service]
Type=simple
ExecStart=${AETHERIUM_DIR}/venv/bin/python3 ${AETHERIUM_DIR}/core/exporter.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=aetherium-exporter

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable aetherium-exporter 2>/dev/null || true
systemctl restart aetherium-exporter || true

# Pull and start Prometheus + Grafana containers
docker compose -f "${MODULE_DIR}/docker-compose.yml" pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" up -d

sleep 5
if docker ps | grep -q aetherium-prometheus; then
    log "Prometheus running at http://aetherium.local:9090"
    log "Grafana running at http://aetherium.local:3000 (admin/aetherium)"
else
    log "WARNING: Monitoring containers not running"
fi
