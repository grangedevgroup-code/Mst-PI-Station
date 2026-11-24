#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${MSTPISTATION_DIR}/templates}"
AP_IFACE="${AP_INTERFACE:-wlan0}"
HOTSPOT_IP="${HOTSPOT_IP:-192.168.42.1}"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-192.168.42.0/24}"
NODE_NAME="${NODE_NAME:-mstpistation-node}"

log() { echo "[dnsmasq/configure] $*"; }

# Parse subnet and derive DHCP range from CIDR (handles /24, /25, /16, etc.)
DHCP_NETMASK=$(python3 -c "
import ipaddress, sys
try:
    net = ipaddress.IPv4Network('${HOTSPOT_SUBNET}', strict=False)
    print(net.netmask)
except Exception:
    print('255.255.255.0')
" 2>/dev/null || echo "255.255.255.0")

# Calculate host range within the subnet
read -r DHCP_START DHCP_END < <(python3 -c "
import ipaddress, sys
try:
    net = ipaddress.IPv4Network('${HOTSPOT_SUBNET}', strict=False)
    hosts = list(net.hosts())
    # Skip first 9 IPs for static assignments (.1=gateway, .2-.9=reserved)
    start_idx = min(9, len(hosts) - 2)
    end_idx = max(start_idx + 1, int(len(hosts) * 0.9))
    print(hosts[start_idx], hosts[end_idx])
except Exception:
    print('192.168.42.10 192.168.42.200')
" 2>/dev/null || echo "192.168.42.10 192.168.42.200")

# Check if uplink exists
UPLINK_AVAILABLE="false"
if ip route | grep -q "default"; then
    UPLINK_AVAILABLE="true"
fi

CAPTIVE_PORTAL="${CAPTIVE_PORTAL:-true}"
[[ "${CAPTIVE_PORTAL}" == "1" ]] && CAPTIVE_PORTAL="true"

"${VENV}/bin/python3" << PYEOF
import sys
sys.path.insert(0, "${MSTPISTATION_DIR}")
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
    "local_domain":     "mstpistation.local",
}
output = tmpl.render(**ctx)
with open("/etc/mstpistation/dnsmasq/dnsmasq.conf", "w") as f:
    f.write(output)
print("Wrote /etc/mstpistation/dnsmasq/dnsmasq.conf")
PYEOF

# Run dnsmasq with our config
cat > /etc/systemd/system/mstpistation-dnsmasq.service << SERVICE
[Unit]
Description=Mst-PI-Station dnsmasq — DHCP and DNS
After=mstpistation-hostapd.service
Requires=mstpistation-hostapd.service

[Service]
Type=simple
ExecStartPre=/usr/sbin/dnsmasq --test --conf-file=/etc/mstpistation/dnsmasq/dnsmasq.conf
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/mstpistation/dnsmasq/dnsmasq.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mstpistation-dnsmasq

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable mstpistation-dnsmasq 2>/dev/null || true
systemctl restart mstpistation-dnsmasq || true

if systemctl is-active mstpistation-dnsmasq &>/dev/null; then
    log "dnsmasq running (AP: ${AP_IFACE}, DHCP: ${DHCP_START}-${DHCP_END})"
else
    log "WARNING: dnsmasq failed. Check: journalctl -u mstpistation-dnsmasq"
fi

log "dnsmasq configuration complete"
