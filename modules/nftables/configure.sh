#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${AETHERIUM_DIR}/templates}"
AP_IFACE="${AP_INTERFACE:-wlan0}"
MESH_IFACE="${MESH_INTERFACE:-wlan0}"
UPLINK_IFACE="${UPLINK_INTERFACE:-eth0}"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-192.168.42.0/24}"
HOTSPOT_IP="${HOTSPOT_IP:-192.168.42.1}"
POLICY="${NFTABLES_POLICY:-field}"

log() { echo "[nftables/configure] $*"; }

# Check if uplink interface exists
UPLINK_AVAILABLE=""
if ip link show "${UPLINK_IFACE}" &>/dev/null 2>&1; then
    UPLINK_AVAILABLE="${UPLINK_IFACE}"
fi

"${VENV}/bin/python3" << PYEOF
import sys
sys.path.insert(0, "${AETHERIUM_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("nftables.conf.j2")

ctx = {
    "ap_interface":     "${AP_IFACE}",
    "mesh_interface":   "${MESH_IFACE}",
    "uplink_interface": "${UPLINK_AVAILABLE}" or None,
    "hotspot_subnet":   "${HOTSPOT_SUBNET}",
    "hotspot_ip":       "${HOTSPOT_IP}",
    "policy":           "${POLICY}",
    "wireguard_port":   51820,
}
output = tmpl.render(**ctx)
with open("/etc/aetherium/nftables.conf", "w") as f:
    f.write(output)
print("Wrote /etc/aetherium/nftables.conf")
PYEOF

# Test config before applying
if nft -f /etc/aetherium/nftables.conf --check 2>/dev/null; then
    nft -f /etc/aetherium/nftables.conf
    log "nftables rules applied (policy=${POLICY})"
else
    log "WARNING: nftables config test failed. Check /etc/aetherium/nftables.conf"
    log "Not applying failed ruleset — system may be unprotected"
fi

# Persist on boot via systemd-nftables override
mkdir -p /etc/systemd/system/nftables.service.d/
cat > /etc/systemd/system/nftables.service.d/aetherium.conf << DROP
[Service]
ExecStart=
ExecStart=/usr/sbin/nft -f /etc/aetherium/nftables.conf
DROP

systemctl enable nftables 2>/dev/null || true

log "nftables configuration complete"
