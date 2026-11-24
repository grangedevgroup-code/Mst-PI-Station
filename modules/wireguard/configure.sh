#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${MSTPISTATION_DIR}/templates}"
WG_DIR="/etc/mstpistation/wireguard"
WG_CONF="/etc/wireguard/mstpistation.conf"

log() { echo "[wireguard/configure] $*"; }

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Read keypair
if [[ ! -f "${WG_DIR}/private.key" ]]; then
    log "No keypair found — running install first"
    bash "${MODULE_DIR}/install.sh"
fi

WG_PRIVATE_KEY=$(cat "${WG_DIR}/private.key")

# Load site config for WireGuard settings
WG_ADDRESS=$(python3 -c "
import yaml, sys
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml')) if __import__('os').path.exists('/etc/mstpistation/mstpistation.yaml') else {}
print(cfg.get('wireguard', {}).get('address', '10.10.0.1/24'))
")
WG_PORT=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml')) if __import__('os').path.exists('/etc/mstpistation/mstpistation.yaml') else {}
print(cfg.get('wireguard', {}).get('port', 51820))
")

# Render config
"${VENV}/bin/python3" << PYEOF
import sys, yaml
sys.path.insert(0, "${MSTPISTATION_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("wireguard.conf.j2")

# Load peers from config
cfg = {}
try:
    with open("/etc/mstpistation/mstpistation.yaml") as f:
        cfg = yaml.safe_load(f) or {}
except Exception:
    pass

wg_cfg = cfg.get("wireguard", {})
peers = wg_cfg.get("peers", [])

ctx = {
    "wg_private_key": "${WG_PRIVATE_KEY}",
    "wg_address":     wg_cfg.get("address", "10.10.0.1").split("/")[0],
    "wg_prefix":      wg_cfg.get("address", "10.10.0.1/24").split("/")[-1],
    "wg_port":        int(wg_cfg.get("port", 51820)),
    "wg_dns":         wg_cfg.get("dns", "1.1.1.1"),
    "wg_subnet":      "10.10.0.0/24",
    "wg_peers":       peers,
}
output = tmpl.render(**ctx)
with open("${WG_CONF}", "w") as f:
    f.write(output)
import os
os.chmod("${WG_CONF}", 0o600)
print("Wrote ${WG_CONF}")
PYEOF

# Enable and start
if command -v systemctl &>/dev/null; then
    systemctl enable wg-quick@mstpistation 2>/dev/null || true
    systemctl restart wg-quick@mstpistation || true
    sleep 1
    if systemctl is-active wg-quick@mstpistation &>/dev/null; then
        log "WireGuard tunnel up (${WG_ADDRESS})"
    else
        log "WireGuard not active — add peers to /etc/mstpistation/mstpistation.yaml wireguard.peers"
    fi
fi

log "Public key: $(cat "${WG_DIR}/public.key")"
log "WireGuard configuration complete"
