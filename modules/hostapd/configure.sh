#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${AETHERIUM_DIR}/templates}"
AP_IFACE="${AP_INTERFACE:-wlan0}"
SSID="${HOTSPOT_SSID:-Aetherium}"
CHANNEL="${HOTSPOT_CHANNEL:-6}"
BAND="${HOTSPOT_BAND:-2.4GHz}"
PASSWORD="${HOTSPOT_PASSWORD:-}"
HIDDEN="${HOTSPOT_HIDDEN:-0}"

log() { echo "[hostapd/configure] $*"; }

# Stop wpa_supplicant on this interface
systemctl stop wpa_supplicant@${AP_IFACE} 2>/dev/null || true
systemctl disable wpa_supplicant@${AP_IFACE} 2>/dev/null || true

# Tell NetworkManager to stop managing AP interface
NM_CONF="/etc/NetworkManager/conf.d/aetherium-unmanaged.conf"
if [[ -f "${NM_CONF}" ]]; then
    # Append if not already there
    grep -q "interface-name:${AP_IFACE}" "${NM_CONF}" || \
        sed -i "s/unmanaged-devices=/unmanaged-devices=interface-name:${AP_IFACE};/" "${NM_CONF}"
else
    mkdir -p /etc/NetworkManager/conf.d
    cat > "${NM_CONF}" << NMCONF
[keyfile]
unmanaged-devices=interface-name:${AP_IFACE}
NMCONF
fi
systemctl reload NetworkManager 2>/dev/null || true

# Bring interface up in a clean state
ip link set "${AP_IFACE}" down 2>/dev/null || true
iw dev "${AP_IFACE}" set type managed 2>/dev/null || true
ip link set "${AP_IFACE}" up
ip addr flush dev "${AP_IFACE}"
ip addr add "${HOTSPOT_IP:-192.168.42.1}/24" dev "${AP_IFACE}"

# Render hostapd config
"${VENV}/bin/python3" << PYEOF
import sys
sys.path.insert(0, "${AETHERIUM_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("hostapd.conf.j2")

ctx = {
    "ap_interface": "${AP_IFACE}",
    "ssid":         "${SSID}",
    "channel":      ${CHANNEL},
    "band":         "${BAND}",
    "password":     "${PASSWORD}",
    "hidden":       ${HIDDEN} == 1 or "${HIDDEN}" == "1",
    "country_code": "",
    "max_clients":  50,
}
output = tmpl.render(**ctx)
with open("/etc/aetherium/hostapd/hostapd.conf", "w") as f:
    f.write(output)
print("Wrote /etc/aetherium/hostapd/hostapd.conf")
PYEOF

chmod 600 /etc/aetherium/hostapd/hostapd.conf

# Enable and start
systemctl enable aetherium-hostapd 2>/dev/null || true
systemctl restart aetherium-hostapd || true
sleep 3

if systemctl is-active aetherium-hostapd &>/dev/null; then
    log "hostapd running (SSID: ${SSID}, iface: ${AP_IFACE}, channel: ${CHANNEL})"
else
    log "WARNING: hostapd failed to start. Check: journalctl -u aetherium-hostapd"
    log "Common fix: ensure ${AP_IFACE} supports AP mode (iw phy phyX info | grep AP)"
fi

log "hostapd configuration complete"
