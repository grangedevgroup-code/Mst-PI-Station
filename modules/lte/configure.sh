#!/usr/bin/env bash
set -euo pipefail

APN="${LTE_APN:-auto}"
log() { echo "[lte/configure] $*"; }

# Find modem
MODEM_IDX=""
if command -v mmcli &>/dev/null; then
    MODEM_IDX=$(mmcli -L 2>/dev/null | grep -oP '/org/freedesktop/ModemManager1/Modem/\K[0-9]+' | head -1)
fi

if [[ -z "${MODEM_IDX}" ]]; then
    log "No modem found. Skipping LTE config. Connect modem and re-run."
    exit 0
fi

log "Modem found at index ${MODEM_IDX}"
mmcli -m "${MODEM_IDX}" 2>/dev/null | head -20

# Auto-detect APN if not set
if [[ "${APN}" == "auto" ]]; then
    OPERATOR=$(mmcli -m "${MODEM_IDX}" 2>/dev/null | grep "operator name" | awk -F: '{print $2}' | xargs)
    log "Operator: ${OPERATOR}. Set APN manually in /etc/aetherium/aetherium.yaml if auto-connect fails."
    APN=""
fi

# Create NetworkManager connection profile for LTE
NM_CONN_FILE="/etc/NetworkManager/system-connections/aetherium-lte.nmconnection"
mkdir -p /etc/NetworkManager/system-connections

cat > "${NM_CONN_FILE}" << NMCONN
[connection]
id=aetherium-lte
type=gsm
autoconnect=true
timestamp=0

[gsm]
${APN:+apn=${APN}}
number=*99#

[ipv4]
method=auto
route-metric=200

[ipv6]
method=auto
NMCONN

chmod 600 "${NM_CONN_FILE}"
nmcli connection reload 2>/dev/null || true
nmcli connection up aetherium-lte 2>/dev/null || true

# Wait for interface
for i in $(seq 1 10); do
    if ip link show usb0 &>/dev/null 2>&1 || ip link show wwan0 &>/dev/null 2>&1; then
        IFACE=$(ip link show usb0 &>/dev/null 2>&1 && echo usb0 || echo wwan0)
        log "LTE interface ${IFACE} is up"
        break
    fi
    sleep 2
done

log "LTE configuration complete"
