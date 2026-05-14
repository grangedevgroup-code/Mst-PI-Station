#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${AETHERIUM_DIR}/templates}"
MESH_IFACE="${MESH_INTERFACE:-wlan0}"
GW_MODE="${BATMAN_GW_MODE:-off}"
NODE_NAME="${NODE_NAME:-aetherium-node}"

log() { echo "[batman-adv/configure] $*"; }

# Render setup script
"${VENV}/bin/python3" << PYEOF
import sys
sys.path.insert(0, "${AETHERIUM_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("batman-adv-setup.sh.j2")

import hashlib
node_suffix = hashlib.md5("${NODE_NAME}".encode()).hexdigest()[:4]
batman_ip = f"10.{int(node_suffix[:2], 16)}.{int(node_suffix[2:], 16)}.1"

ctx = {
    "mesh_interface":  "${MESH_IFACE}",
    "gw_mode":         "${GW_MODE}",
    "gw_bandwidth":    "100mbit/100mbit",
    "mesh_frequency":  2412,
    "batman_ip":       batman_ip,
}
output = tmpl.render(**ctx)
with open("/etc/aetherium/batman-adv-setup.sh", "w") as f:
    f.write(output)
print(f"Rendered batman-adv setup script, batman_ip={batman_ip}")
PYEOF

chmod +x /etc/aetherium/batman-adv-setup.sh

# NetworkManager: mark mesh interface as unmanaged
NM_CONF="/etc/NetworkManager/conf.d/aetherium-unmanaged.conf"
if [[ -d /etc/NetworkManager/conf.d ]]; then
    cat > "${NM_CONF}" << NMCONF
[keyfile]
unmanaged-devices=interface-name:${MESH_IFACE};interface-name:bat0
NMCONF
    log "NetworkManager: ${MESH_IFACE} and bat0 marked unmanaged"
    systemctl reload NetworkManager 2>/dev/null || true
fi

# Enable and start batman-adv service
if command -v systemctl &>/dev/null; then
    systemctl enable batman-adv 2>/dev/null || true
    systemctl restart batman-adv || true
    sleep 2
    if ip link show bat0 &>/dev/null; then
        log "bat0 interface is up"
    else
        log "WARNING: bat0 not found, batman-adv may not have started"
    fi
fi

log "batman-adv configuration complete (mesh_iface=${MESH_IFACE}, gw=${GW_MODE})"
