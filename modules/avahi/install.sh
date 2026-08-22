#!/usr/bin/env bash
set -euo pipefail
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[avahi] $*"; }

case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq avahi-daemon avahi-utils libnss-mdns
        ;;
    fedora)
        dnf install -y avahi avahi-tools nss-mdns
        ;;
    arch)
        pacman -S --noconfirm --needed avahi nss-mdns
        ;;
    *)
        log "WARNING: Install avahi-daemon manually for ${DISTRO_FAMILY}"
        ;;
esac

# Ensure nss-mdns is active in /etc/nsswitch.conf
if ! grep -q "mdns4_minimal" /etc/nsswitch.conf 2>/dev/null; then
    sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' \
        /etc/nsswitch.conf 2>/dev/null || true
fi

mkdir -p /etc/avahi/services
systemctl enable avahi-daemon 2>/dev/null || true
log "Avahi installed"
