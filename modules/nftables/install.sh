#!/usr/bin/env bash
set -euo pipefail
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[nftables] $*"; }

case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nftables ;;
    fedora) dnf install -y nftables ;;
    arch)   pacman -S --noconfirm --needed nftables ;;
    *)      log "WARNING: Install nftables manually" ;;
esac

# Enable IP forwarding
cat > /etc/sysctl.d/99-aetherium.conf << SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
SYSCTL
sysctl -p /etc/sysctl.d/99-aetherium.conf >/dev/null

log "nftables installation complete"
