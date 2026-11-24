#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

# Docker modules are not supported on OpenWrt (no Docker available)
if [[ "${DISTRO_FAMILY:-}" == "openwrt" ]]; then
    echo "[monitoring] Skipping — Docker not available on OpenWrt"
    exit 0
fi
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"

log() { echo "[monitoring] $*"; }

# Docker required for Prometheus+Grafana
if ! command -v docker &>/dev/null; then
    case "${DISTRO_FAMILY}" in
        debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io ;;
        fedora) dnf install -y docker ;;
        arch)   pacman -S --noconfirm --needed docker ;;
    esac
    systemctl enable docker 2>/dev/null || true
    systemctl start docker || true
fi

# Install native node_exporter (more accurate than container on Pi)
NE_ARCH="arm64"
case "$(uname -m)" in
    x86_64|amd64) NE_ARCH="amd64" ;;
    aarch64)      NE_ARCH="arm64" ;;
    armv7l)       NE_ARCH="armv7" ;;
    armv6l)       NE_ARCH="armv6" ;;
esac

NE_VER="1.8.1"
NE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NE_VER}/node_exporter-${NE_VER}.linux-${NE_ARCH}.tar.gz"
NE_TMP="/tmp/node_exporter.tar.gz"

if ! command -v node_exporter &>/dev/null; then
    log "Installing node_exporter ${NE_VER} (${NE_ARCH})..."
    wget -q -O "${NE_TMP}" "${NE_URL}" && \
    tar -xzf "${NE_TMP}" -C /usr/local/bin \
        --strip-components=1 \
        "node_exporter-${NE_VER}.linux-${NE_ARCH}/node_exporter" && \
    rm -f "${NE_TMP}"
fi

# node_exporter systemd service
cat > /etc/systemd/system/mstpistation-node-exporter.service << SVC
[Unit]
Description=Mst-PI-Station Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes \
    --web.listen-address=127.0.0.1:9100
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable mstpistation-node-exporter 2>/dev/null || true
systemctl restart mstpistation-node-exporter || true

# Install mstpistation custom exporter (batman-adv, RNS, etc.)
"${VENV}/bin/pip" install --quiet prometheus_client

mkdir -p /var/lib/mstpistation/monitoring
log "Monitoring stack ready"
