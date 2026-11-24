#!/usr/bin/env bash
set -euo pipefail

source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[hostapd] $*"; }

case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq hostapd
        # Prevent hostapd from being started by the default init script
        systemctl unmask hostapd 2>/dev/null || true
        systemctl disable hostapd 2>/dev/null || true
        ;;
    fedora)
        dnf install -y hostapd
        systemctl disable hostapd 2>/dev/null || true
        ;;
    arch)
        pacman -S --noconfirm --needed hostapd
        systemctl disable hostapd 2>/dev/null || true
        ;;
    *)
        log "WARNING: Please install hostapd manually"
        ;;
esac

if command -v hostapd &>/dev/null; then
    log "hostapd $(hostapd -v 2>&1 | head -1) installed"
else
    log "ERROR: hostapd not found after install"
    exit 1
fi

# Stop wpa_supplicant on the AP interface — it conflicts with hostapd
systemctl stop wpa_supplicant 2>/dev/null || true

# Install Mst-PI-Station hostapd systemd service
install -m644 "${MODULE_DIR}/systemd/mstpistation-hostapd.service" /etc/systemd/system/
systemctl daemon-reload

mkdir -p /etc/mstpistation/hostapd
log "hostapd installation complete"
