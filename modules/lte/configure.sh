#!/usr/bin/env bash
set -euo pipefail

LTE_APN="${LTE_APN:-auto}"
LTE_ROAMING="${LTE_ROAMING:-0}"
log() { echo "[lte/configure] $*"; }

# ── Modem detection ──────────────────────────────────────────────────────────
MODEM_IDX=""
if command -v mmcli &>/dev/null; then
    MODEM_IDX=$(mmcli -L 2>/dev/null | grep -oP '/org/freedesktop/ModemManager1/Modem/\K[0-9]+' | head -1)
fi

if [[ -z "${MODEM_IDX}" ]]; then
    log "No modem found — will retry when modem is connected."
    log "Run 'mstpistation module enable lte' after connecting modem."
    exit 0
fi

log "Modem found: index ${MODEM_IDX}"
mmcli -m "${MODEM_IDX}" 2>/dev/null | grep -E "manufacturer|model|state|access tech|operator" || true

# ── APN auto-detection ───────────────────────────────────────────────────────
# Strategy: operator name match → IMSI prefix match → leave blank (let network assign)
if [[ "${LTE_APN}" == "auto" ]]; then
    OPERATOR=$(mmcli -m "${MODEM_IDX}" 2>/dev/null \
        | grep -i "operator name" | awk -F': ' '{print $NF}' | xargs | tr '[:upper:]' '[:lower:]')
    IMSI=$(mmcli -m "${MODEM_IDX}" --sim 2>/dev/null \
        | grep -i "imsi" | awk -F': ' '{print $NF}' | xargs 2>/dev/null || echo "")

    log "Operator: ${OPERATOR:-unknown} | IMSI prefix: ${IMSI:0:6}"

    # IMSI prefix (MCC+MNC) → APN database
    declare -A IMSI_APN
    # United States
    IMSI_APN["310410"]="broaddata"          # AT&T
    IMSI_APN["310260"]="fast.t-mobile.com"  # T-Mobile
    IMSI_APN["311480"]="vzwinternet"         # Verizon
    IMSI_APN["311490"]="vzwinternet"
    IMSI_APN["310120"]="internet"            # Sprint
    IMSI_APN["312250"]="internet"            # US Cellular
    # Canada
    IMSI_APN["302220"]="internet.com"        # Telus
    IMSI_APN["302610"]="wap.rogers.com"      # Rogers
    IMSI_APN["302720"]="internet.com"        # Rogers (old)
    IMSI_APN["302370"]="internet"            # Fido
    # UK
    IMSI_APN["234010"]="giffgaff.com"
    IMSI_APN["234030"]="mobile.vodafone.net"
    IMSI_APN["234015"]="everywhere"          # EE
    IMSI_APN["234020"]="three.co.uk"
    IMSI_APN["234050"]="three.co.uk"         # T-Mobile UK
    # Germany
    IMSI_APN["26201"]="internet.telekom"
    IMSI_APN["26202"]="web.vodafone.de"
    IMSI_APN["26203"]="internet"             # O2 DE
    # Australia
    IMSI_APN["50501"]="telstra.internet"
    IMSI_APN["50502"]="VodafoneAU"
    IMSI_APN["50503"]="yesinternet"          # Optus
    # Japan
    IMSI_APN["44010"]="spmode.ne.jp"
    IMSI_APN["44020"]="lte.nttdocomo.ne.jp"

    # Operator name → APN fallback table
    declare -A NAME_APN
    NAME_APN["at&t"]="broaddata"
    NAME_APN["att"]="broaddata"
    NAME_APN["t-mobile"]="fast.t-mobile.com"
    NAME_APN["tmobile"]="fast.t-mobile.com"
    NAME_APN["verizon"]="vzwinternet"
    NAME_APN["sprint"]="internet"
    NAME_APN["us cellular"]="internet"
    NAME_APN["rogers"]="wap.rogers.com"
    NAME_APN["telus"]="internet.com"
    NAME_APN["bell"]="pda.bell.ca"
    NAME_APN["vodafone"]="web.vodafone.net"
    NAME_APN["ee"]="everywhere"
    NAME_APN["three"]="three.co.uk"
    NAME_APN["o2"]="mobile.o2.co.uk"
    NAME_APN["telekom"]="internet.telekom"
    NAME_APN["telstra"]="telstra.internet"
    NAME_APN["optus"]="yesinternet"
    NAME_APN["docomo"]="spmode.ne.jp"
    NAME_APN["softbank"]="softbank"
    NAME_APN["au"]="au-net.ne.jp"

    # Try IMSI prefix first (most reliable)
    DETECTED_APN=""
    for prefix_len in 6 5; do
        prefix="${IMSI:0:${prefix_len}}"
        if [[ -n "${prefix}" ]] && [[ -v "IMSI_APN[${prefix}]" ]]; then
            DETECTED_APN="${IMSI_APN[${prefix}]}"
            log "APN detected from IMSI prefix (${prefix}): ${DETECTED_APN}"
            break
        fi
    done

    # Fall back to operator name match
    if [[ -z "${DETECTED_APN}" ]] && [[ -n "${OPERATOR}" ]]; then
        for name_key in "${!NAME_APN[@]}"; do
            if [[ "${OPERATOR}" == *"${name_key}"* ]]; then
                DETECTED_APN="${NAME_APN[${name_key}]}"
                log "APN detected from operator name (${OPERATOR}): ${DETECTED_APN}"
                break
            fi
        done
    fi

    if [[ -n "${DETECTED_APN}" ]]; then
        LTE_APN="${DETECTED_APN}"
    else
        log "APN not in database for '${OPERATOR}' — leaving blank (NetworkManager will negotiate)"
        LTE_APN=""
    fi
fi

# ── Connect: NetworkManager preferred, mmcli direct fallback ─────────────────
NM_AVAILABLE=0
command -v nmcli &>/dev/null && systemctl is-active NetworkManager &>/dev/null && NM_AVAILABLE=1

if [[ "${NM_AVAILABLE}" == "1" ]]; then
    log "Configuring via NetworkManager"
    NM_CONN_FILE="/etc/NetworkManager/system-connections/mstpistation-lte.nmconnection"
    mkdir -p /etc/NetworkManager/system-connections

    cat > "${NM_CONN_FILE}" << NMCONN
[connection]
id=mstpistation-lte
type=gsm
autoconnect=true
timestamp=0

[gsm]
${LTE_APN:+apn=${LTE_APN}}
number=*99#
${LTE_ROAMING:+allow-roaming=${LTE_ROAMING}}

[ipv4]
method=auto
route-metric=200

[ipv6]
method=auto
NMCONN
    chmod 600 "${NM_CONN_FILE}"
    nmcli connection reload 2>/dev/null || true
    nmcli connection up mstpistation-lte 2>/dev/null || log "NM connection pending — modem may still be initializing"

elif command -v mmcli &>/dev/null; then
    # Fallback: connect directly via mmcli (works on systemd-networkd or minimal systems)
    log "NetworkManager not active — using mmcli direct connect"
    CONNECT_ARGS=""
    [[ -n "${LTE_APN}" ]] && CONNECT_ARGS="apn=${LTE_APN}"
    mmcli -m "${MODEM_IDX}" --simple-connect="${CONNECT_ARGS}" 2>/dev/null || \
        log "WARNING: mmcli simple-connect failed — modem may need a moment, check: mmcli -m ${MODEM_IDX}"

    # Write a systemd-networkd .network file so the interface gets DHCP automatically
    if [[ -d /etc/systemd/network ]]; then
        for iface_candidate in usb0 wwan0 wwan0_0; do
            cat > "/etc/systemd/network/20-mstpistation-lte-${iface_candidate}.network" << NETD
[Match]
Name=${iface_candidate}

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=200
UseDNS=yes
NETD
        done
        systemctl reload systemd-networkd 2>/dev/null || true
        log "systemd-networkd .network files written for LTE interface"
    fi
else
    log "WARNING: Neither NetworkManager nor mmcli direct-connect available"
fi

# ── Wait for interface ───────────────────────────────────────────────────────
log "Waiting for LTE interface..."
IFACE=""
for i in $(seq 1 15); do
    for candidate in usb0 wwan0 wwan0_0 wwan1; do
        if ip link show "${candidate}" &>/dev/null 2>&1; then
            IFACE="${candidate}"
            break 2
        fi
    done
    # Also check for any ppp/rmnet interface from mmcli
    IFACE=$(mmcli -m "${MODEM_IDX}" --simple-status 2>/dev/null \
        | grep -oP 'bearer.*interface.*: \K\S+' | head -1 || echo "")
    [[ -n "${IFACE}" ]] && break
    sleep 2
done

if [[ -n "${IFACE}" ]]; then
    log "LTE interface: ${IFACE}"
    # Give IP assignment a moment
    sleep 2
    IP=$(ip -4 addr show "${IFACE}" 2>/dev/null | grep inet | awk '{print $2}' | head -1 || echo "")
    [[ -n "${IP}" ]] && log "LTE IP: ${IP}" || log "IP not yet assigned — DHCP in progress"
else
    log "WARNING: LTE interface not up yet. Check: mmcli -m ${MODEM_IDX}"
fi

log "LTE configuration complete${LTE_APN:+ (APN: ${LTE_APN})}"
