#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
TEMPLATES_DIR="${TEMPLATES_DIR:-${MSTPISTATION_DIR}/templates}"
AP_IFACE="${AP_INTERFACE:-wlan0}"
SSID="${HOTSPOT_SSID:-Mst-PI-Station}"
CHANNEL="${HOTSPOT_CHANNEL:-auto}"
BAND="${HOTSPOT_BAND:-2.4GHz}"
PASSWORD="${HOTSPOT_PASSWORD:-}"
HIDDEN="${HOTSPOT_HIDDEN:-0}"
REGULATORY_DOMAIN="${REGULATORY_DOMAIN:-}"

log() { echo "[hostapd/configure] $*"; }

# ── Validate AP mode support ─────────────────────────────────────────────────
PHY=$(iw dev "${AP_IFACE}" info 2>/dev/null | awk '/wiphy/{print "phy"$2}' || echo "")
if [[ -n "${PHY}" ]]; then
    if ! iw phy "${PHY}" info 2>/dev/null | grep -qE "^\s+\* AP$|^\s+\* AP/VLAN"; then
        log "WARNING: ${AP_IFACE} (${PHY}) may not support AP mode"
        log "Attempting anyway. If hostapd fails, check: iw phy ${PHY} info | grep -A2 'Supported interface modes'"
    fi
fi

# ── Auto-detect regulatory domain if not provided ───────────────────────────
if [[ -z "${REGULATORY_DOMAIN}" ]]; then
    # Check iw reg get
    REGULATORY_DOMAIN=$(iw reg get 2>/dev/null | awk '/^country /{print $2}' | tr -d ':' | head -1 || echo "")
    # Derive from timezone if still empty
    if [[ -z "${REGULATORY_DOMAIN}" ]] || [[ "${REGULATORY_DOMAIN}" == "00" ]]; then
        TZ=$(timedatectl show --property=Timezone --value 2>/dev/null \
             || cat /etc/timezone 2>/dev/null \
             || readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' \
             || echo "")
        case "${TZ}" in
            America/*)          REGULATORY_DOMAIN="US" ;;
            Europe/London|Europe/Dublin) REGULATORY_DOMAIN="GB" ;;
            Europe/*)           REGULATORY_DOMAIN="DE" ;;
            Australia/*)        REGULATORY_DOMAIN="AU" ;;
            Asia/Tokyo)         REGULATORY_DOMAIN="JP" ;;
            Asia/Shanghai|Asia/Beijing) REGULATORY_DOMAIN="CN" ;;
            Asia/Kolkata)       REGULATORY_DOMAIN="IN" ;;
            Asia/Seoul)         REGULATORY_DOMAIN="KR" ;;
            Pacific/Auckland)   REGULATORY_DOMAIN="NZ" ;;
        esac
    fi
fi

# Set regulatory domain in kernel if we have one
if [[ -n "${REGULATORY_DOMAIN}" ]] && [[ "${REGULATORY_DOMAIN}" != "00" ]]; then
    iw reg set "${REGULATORY_DOMAIN}" 2>/dev/null || true
    log "Regulatory domain: ${REGULATORY_DOMAIN}"
fi

# ── Auto-select least-congested channel ─────────────────────────────────────
# NOTE: this function must be defined BEFORE it is called below.
auto_select_channel() {
    local iface="$1" band="$2"
    # Bring up interface briefly for scan (it may be down)
    ip link set "${iface}" up 2>/dev/null || true

    # Count APs per channel from scan results
    if [[ "${band}" == "5GHz" ]]; then
        CANDIDATES=(36 40 44 48 149 153 157 161)
    else
        CANDIDATES=(1 6 11)
    fi

    declare -A CHANNEL_COUNT
    for c in "${CANDIDATES[@]}"; do CHANNEL_COUNT[$c]=0; done

    if command -v iw &>/dev/null; then
        while IFS= read -r line; do
            if [[ "${line}" =~ "DS Parameter set: channel"\ ([0-9]+) ]]; then
                ch="${BASH_REMATCH[1]}"
                for c in "${CANDIDATES[@]}"; do
                    if [[ "${ch}" == "${c}" ]]; then
                        CHANNEL_COUNT[$c]=$((CHANNEL_COUNT[$c] + 1))
                        break
                    fi
                done
            fi
        done < <(iw dev "${iface}" scan 2>/dev/null || echo "")
    fi

    # Pick the candidate with fewest APs
    BEST_CH="${CANDIDATES[0]}"
    BEST_COUNT=9999
    for c in "${CANDIDATES[@]}"; do
        cnt="${CHANNEL_COUNT[$c]:-0}"
        if [[ "${cnt}" -lt "${BEST_COUNT}" ]]; then
            BEST_COUNT="${cnt}"
            BEST_CH="${c}"
        fi
    done
    echo "${BEST_CH}"
}

if [[ "${CHANNEL}" == "auto" ]] || [[ "${CHANNEL}" == "0" ]]; then
    log "Scanning for least-congested channel..."
    CHANNEL=$(auto_select_channel "${AP_IFACE}" "${BAND}" || echo "6")
    log "Auto-selected channel: ${CHANNEL}"
fi

# ── Stop conflicting services ────────────────────────────────────────────────
systemctl stop "wpa_supplicant@${AP_IFACE}" 2>/dev/null || true
systemctl disable "wpa_supplicant@${AP_IFACE}" 2>/dev/null || true
# Also stop the global wpa_supplicant if it has this interface
if systemctl is-active wpa_supplicant &>/dev/null; then
    wpa_cli -i "${AP_IFACE}" terminate 2>/dev/null || true
fi

# ── NetworkManager unmanage (skip if NM not running) ────────────────────────
if systemctl is-active NetworkManager &>/dev/null 2>&1 || command -v nmcli &>/dev/null; then
    NM_CONF="/etc/NetworkManager/conf.d/mstpistation-unmanaged.conf"
    mkdir -p /etc/NetworkManager/conf.d
    if [[ -f "${NM_CONF}" ]]; then
        grep -q "interface-name:${AP_IFACE}" "${NM_CONF}" || \
            sed -i "s/unmanaged-devices=/unmanaged-devices=interface-name:${AP_IFACE};/" "${NM_CONF}"
    else
        cat > "${NM_CONF}" << NMCONF
[keyfile]
unmanaged-devices=interface-name:${AP_IFACE}
NMCONF
    fi
    systemctl reload NetworkManager 2>/dev/null || true
fi

# For systemd-networkd systems: write a .network file that ignores this interface
if [[ -d /etc/systemd/network ]] && ! systemctl is-active NetworkManager &>/dev/null 2>&1; then
    cat > "/etc/systemd/network/10-mstpistation-ap-${AP_IFACE}.network" << NETD
[Match]
Name=${AP_IFACE}

[Link]
Unmanaged=yes
NETD
    systemctl reload systemd-networkd 2>/dev/null || true
fi

# ── Interface setup ──────────────────────────────────────────────────────────
ip link set "${AP_IFACE}" down 2>/dev/null || true
iw dev "${AP_IFACE}" set type managed 2>/dev/null || true
ip link set "${AP_IFACE}" up
ip addr flush dev "${AP_IFACE}"
ip addr add "${HOTSPOT_IP:-192.168.42.1}/24" dev "${AP_IFACE}"

# ── Render hostapd config ────────────────────────────────────────────────────
"${VENV}/bin/python3" << PYEOF
import sys
sys.path.insert(0, "${MSTPISTATION_DIR}")
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader("${TEMPLATES_DIR}"))
tmpl = env.get_template("hostapd.conf.j2")

ctx = {
    "ap_interface": "${AP_IFACE}",
    "ssid":         "${SSID}",
    "channel":      int("${CHANNEL}"),
    "band":         "${BAND}",
    "password":     "${PASSWORD}",
    "hidden":       "${HIDDEN}" == "1",
    "country_code": "${REGULATORY_DOMAIN}",
    "max_clients":  50,
}
output = tmpl.render(**ctx)
with open("/etc/mstpistation/hostapd/hostapd.conf", "w") as f:
    f.write(output)
print("Wrote /etc/mstpistation/hostapd/hostapd.conf")
PYEOF

chmod 600 /etc/mstpistation/hostapd/hostapd.conf

systemctl enable mstpistation-hostapd 2>/dev/null || true
systemctl restart mstpistation-hostapd || true
sleep 3

if systemctl is-active mstpistation-hostapd &>/dev/null; then
    log "hostapd running — SSID: ${SSID} | iface: ${AP_IFACE} | channel: ${CHANNEL}${REGULATORY_DOMAIN:+ | country: ${REGULATORY_DOMAIN}}"
else
    log "WARNING: hostapd failed to start."
    log "Diagnose: journalctl -u mstpistation-hostapd"
    log "AP mode check: iw phy ${PHY:-phy0} info | grep -A10 'Supported interface modes'"
fi
