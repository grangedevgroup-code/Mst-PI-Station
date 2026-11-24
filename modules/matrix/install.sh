#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

# Docker modules are not supported on OpenWrt (no Docker available)
if [[ "${DISTRO_FAMILY:-}" == "openwrt" ]]; then
    echo "[matrix] Skipping — Docker not available on OpenWrt"
    exit 0
fi

log() { echo "[matrix] $*"; }

if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    case "${DISTRO_FAMILY}" in
        debian)
            curl -fsSL https://get.docker.com | sh 2>/dev/null || \
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io
            ;;
        fedora) dnf install -y docker ;;
        arch)   pacman -S --noconfirm --needed docker ;;
        *)      log "WARNING: Install Docker manually" ;;
    esac
    systemctl enable docker 2>/dev/null || true
    systemctl start docker || true
fi

mkdir -p /var/lib/mstpistation/matrix
chmod 755 /var/lib/mstpistation/matrix
log "Matrix Conduit ready to deploy"
