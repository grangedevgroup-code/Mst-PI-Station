#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${AETHERIUM_DIR}/templates}"
AP_IFACE="${AP_INTERFACE:-wlan0}"
HOTSPOT_IP="${HOTSPOT_IP:-192.168.42.1}"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-192.168.42.0/24}"
NODE_NAME="${NODE_NAME:-aetherium-node}"

log() { echo "[dnsmasq/configure] $*"; }

# Parse subnet into components
IFS='.' read -r a b c d <<< "${HOTSPOT_IP}"
DHCP_START="${a}.${b}.${c}.10"
DHCP_END="${a}.${b}.${c}.200"
DHCP_NETMASK="255.255.255.0"

# Check if uplink exists
UPLINK_AVAILABLE="false"
if ip route | grep -q "default"; then
    UPLINK_AVAILABLE="true"
fi

CAPTIVE_PORTAL="${CAPTIVE_PORTAL:-true}"
[[ "${CAPTIVE_PORTAL}" == "1" ]] && CAPTIVE_PORTAL="true"

"${VENV}/bin/python3" << PYEOF
import sys
sys.path.insert(0, "${AETHERIUM_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("dnsmasq.conf.j2")

ctx = {
    "ap_interface":     "${AP_IFACE}",
    "hotspot_ip":       "${HOTSPOT_IP}",
    "dhcp_start":       "${DHCP_START}",
    "dhcp_end":         "${DHCP_END}",
    "dhcp_netmask":     "${DHCP_NETMASK}",
    "dhcp_lease_time":  "2h",
    "node_name":        "${NODE_NAME}",
    "captive_portal":   "${CAPTIVE_PORTAL}" == "true",
    "uplink_available": "${UPLINK_AVAILABLE}" == "true",
    "local_domain":     "aetherium.local",
}
output = tmpl.render(**ctx)
with open("/etc/aetherium/dnsmasq/dnsmasq.conf", "w") as f:
    f.write(output)
print("Wrote /etc/aetherium/dnsmasq/dnsmasq.conf")
PYEOF

# Run dnsmasq with our config
cat > /etc/systemd/system/aetherium-dnsmasq.service << SERVICE
[Unit]
Description=Aetherium dnsmasq — DHCP and DNS
After=aetherium-hostapd.service
Requires=aetherium-hostapd.service

[Service]
Type=simple
ExecStartPre=/usr/sbin/dnsmasq --test --conf-file=/etc/aetherium/dnsmasq/dnsmasq.conf
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/aetherium/dnsmasq/dnsmasq.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=aetherium-dnsmasq

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable aetherium-dnsmasq 2>/dev/null || true
systemctl restart aetherium-dnsmasq || true

if systemctl is-active aetherium-dnsmasq &>/dev/null; then
    log "dnsmasq running (AP: ${AP_IFACE}, DHCP: ${DHCP_START}-${DHCP_END})"
else
    log "WARNING: dnsmasq failed. Check: journalctl -u aetherium-dnsmasq"
fi

log "dnsmasq configuration complete"
