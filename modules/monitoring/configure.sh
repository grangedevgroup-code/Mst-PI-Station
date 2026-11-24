#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/mstpistation/modules/monitoring}"
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"

log() { echo "[monitoring/configure] $*"; }

mkdir -p /var/lib/mstpistation/prometheus /var/lib/mstpistation/grafana
chmod 777 /var/lib/mstpistation/grafana  # Grafana writes as its own uid

# Generate (or load existing) Grafana admin password
GRAFANA_PASS_FILE="/etc/mstpistation/monitoring/grafana-admin-password"
mkdir -p /etc/mstpistation/monitoring
chmod 700 /etc/mstpistation/monitoring

if [[ ! -f "${GRAFANA_PASS_FILE}" ]]; then
    # Generate a random 16-char alphanumeric password
    GRAFANA_PASS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16 2>/dev/null || \
                   python3 -c "import secrets; print(secrets.token_urlsafe(12))")
    echo "${GRAFANA_PASS}" > "${GRAFANA_PASS_FILE}"
    chmod 600 "${GRAFANA_PASS_FILE}"
    log "Generated Grafana admin password (saved to ${GRAFANA_PASS_FILE})"
else
    GRAFANA_PASS=$(cat "${GRAFANA_PASS_FILE}")
fi

# Inject password into docker-compose override
cat > "${MODULE_DIR}/docker-compose.override.yml" << OVERRIDE
version: "3.8"
services:
  grafana:
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
      - GF_SECURITY_ADMIN_USER=admin
OVERRIDE

# Deploy Mst-PI-Station exporter systemd service
cat > /etc/systemd/system/mstpistation-exporter.service << SVC
[Unit]
Description=Mst-PI-Station Custom Metrics Exporter
After=network.target

[Service]
Type=simple
ExecStart=${MSTPISTATION_DIR}/venv/bin/python3 ${MSTPISTATION_DIR}/core/exporter.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mstpistation-exporter

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable mstpistation-exporter 2>/dev/null || true
systemctl restart mstpistation-exporter || true

# Pull and start Prometheus + Grafana containers
docker compose -f "${MODULE_DIR}/docker-compose.yml" \
               -f "${MODULE_DIR}/docker-compose.override.yml" \
               pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" \
               -f "${MODULE_DIR}/docker-compose.override.yml" \
               up -d

sleep 5
if docker ps | grep -q mstpistation-prometheus; then
    log "Prometheus: http://mstpistation.local:9090"
    log "Grafana:    http://mstpistation.local:3001 (admin / $(cat "${GRAFANA_PASS_FILE}"))"
    log "Grafana password also stored in: ${GRAFANA_PASS_FILE}"
else
    log "WARNING: Monitoring containers not running — check: docker compose -f ${MODULE_DIR}/docker-compose.yml logs"
fi
