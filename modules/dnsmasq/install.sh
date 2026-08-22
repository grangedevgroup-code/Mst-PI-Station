#!/usr/bin/env bash
set -euo pipefail
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[dnsmasq] $*"; }

case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsmasq ;;
    fedora) dnf install -y dnsmasq ;;
    arch)   pacman -S --noconfirm --needed dnsmasq ;;
    *)      log "WARNING: Install dnsmasq manually" ;;
esac

# Disable system dnsmasq — we run our own instance
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

# Disable NetworkManager's internal dnsmasq plugin
NM_MAIN="/etc/NetworkManager/NetworkManager.conf"
if [[ -f "${NM_MAIN}" ]]; then
    if ! grep -q "^dns=none" "${NM_MAIN}"; then
        # Add or replace dns= setting
        if grep -q "^\[main\]" "${NM_MAIN}"; then
            sed -i '/^\[main\]/a dns=none' "${NM_MAIN}"
        fi
        log "Disabled NetworkManager internal DNS"
    fi
fi

mkdir -p /etc/aetherium/dnsmasq /var/log/aetherium

log "dnsmasq installation complete"
