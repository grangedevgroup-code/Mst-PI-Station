#!/usr/bin/env bash
# Reticulum configuration module
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
RNS_CONFIG_DIR="${RNS_CONFIG_DIR:-/etc/reticulum}"
TEMPLATES_DIR="${TEMPLATES_DIR:-${MSTPISTATION_DIR}/templates}"
RNS_USER="reticulum"

log() { echo "[reticulum/configure] $*"; }

mkdir -p "${RNS_CONFIG_DIR}"
chown "${RNS_USER}:${RNS_USER}" "${RNS_CONFIG_DIR}"
chmod 750 "${RNS_CONFIG_DIR}"

# Determine if we're running as a transport node (relay profiles)
RNS_TRANSPORT="false"
case "${NODE_PROFILE:-}" in
    relay|mesh-hub|lte-gateway|solar-relay) RNS_TRANSPORT="true" ;;
esac

# Build interface context for Jinja2
AUTOINTERFACE_ENABLED="true"
TCP_SERVER_ENABLED="false"
case "${NODE_PROFILE:-}" in
    relay|mesh-hub|lte-gateway) TCP_SERVER_ENABLED="true" ;;
esac

RNODE_ENABLED="false"
if [[ -n "${RNODE_PORT:-}" ]]; then
    RNODE_ENABLED="true"
fi

# Render config using Python Jinja2
"${VENV}/bin/python3" << PYEOF
import sys, os
sys.path.insert(0, "${MSTPISTATION_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("reticulum.conf.j2")

ctx = {
    "node_profile":         "${NODE_PROFILE:-relay}",
    "rns_transport":        ${RNS_TRANSPORT} == "true" or "${RNS_TRANSPORT}" == "true",
    "autointerface_enabled": True,
    "autointerface_group":  "mstpistation-${NODE_PROFILE:-relay}",
    "tcp_server_enabled":   "${TCP_SERVER_ENABLED}" == "true",
    "tcp_server_port":      4242,
    "rnode_enabled":        "${RNODE_ENABLED}" == "true",
    "rnode_port":           "${RNODE_PORT:-}",
    "rnode_frequency":      int("${RNODE_FREQ:-915000000}"),
    "rnode_bandwidth":      int("${RNODE_BW:-125000}"),
    "rnode_sf":             int("${RNODE_SF:-7}"),
    "rnode_coding_rate":    5,
    "rnode_tx_power":       int("${RNODE_TX_POWER:-17}"),
    "extra_interfaces":     [],
}

output = tmpl.render(**ctx)
with open("${RNS_CONFIG_DIR}/config", "w") as f:
    f.write(output)
print(f"Wrote {RNS_CONFIG_DIR}/config")
PYEOF

chown "${RNS_USER}:${RNS_USER}" "${RNS_CONFIG_DIR}/config"
chmod 640 "${RNS_CONFIG_DIR}/config"

# Enable and start service
if command -v systemctl &>/dev/null; then
    systemctl enable reticulum 2>/dev/null || true
    systemctl restart reticulum || true
    sleep 2
    if systemctl is-active reticulum &>/dev/null; then
        log "Reticulum service running"
    else
        log "WARNING: Reticulum service not active — check: journalctl -u reticulum"
    fi
fi

log "Reticulum configuration complete"
