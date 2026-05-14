#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${MODULE_DIR:-/opt/aetherium/modules/monitoring}"
AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"

log() { echo "[monitoring/configure] $*"; }

mkdir -p /var/lib/aetherium/prometheus /var/lib/aetherium/grafana
chmod 777 /var/lib/aetherium/grafana  # Grafana writes as its own uid

# Generate (or load existing) Grafana admin password
GRAFANA_PASS_FILE="/etc/aetherium/monitoring/grafana-admin-password"
mkdir -p /etc/aetherium/monitoring
chmod 700 /etc/aetherium/monitoring

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
docker compose -f "${MODULE_DIR}/docker-compose.yml" \
               -f "${MODULE_DIR}/docker-compose.override.yml" \
               pull --quiet 2>/dev/null || true
docker compose -f "${MODULE_DIR}/docker-compose.yml" \
               -f "${MODULE_DIR}/docker-compose.override.yml" \
               up -d

sleep 5
if docker ps | grep -q aetherium-prometheus; then
    log "Prometheus: http://aetherium.local:9090"
    log "Grafana:    http://aetherium.local:3001 (admin / $(cat "${GRAFANA_PASS_FILE}"))"
    log "Grafana password also stored in: ${GRAFANA_PASS_FILE}"
else
    log "WARNING: Monitoring containers not running — check: docker compose -f ${MODULE_DIR}/docker-compose.yml logs"
fi
