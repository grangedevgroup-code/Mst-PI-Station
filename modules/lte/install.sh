#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[lte] $*"; }

case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            modemmanager libmm-glib0 \
            network-manager-gnome usb-modeswitch usb-modeswitch-data 2>/dev/null || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            modemmanager usb-modeswitch 2>/dev/null || true
        ;;
    fedora)
        dnf install -y ModemManager usb_modeswitch 2>/dev/null || true
        ;;
    arch)
        pacman -S --noconfirm --needed modemmanager usb_modeswitch 2>/dev/null || true
        ;;
esac

systemctl enable ModemManager 2>/dev/null || true
systemctl start ModemManager 2>/dev/null || true

sleep 3

if command -v mmcli &>/dev/null; then
    MODEMS=$(mmcli -L 2>/dev/null)
    if [[ -n "${MODEMS}" ]]; then
        log "LTE modems found: ${MODEMS}"
    else
        log "No LTE modem detected. Connect USB modem and run: mstpistation module enable lte"
    fi
fi

log "LTE stack installation complete"
