#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

# Docker modules are not supported on OpenWrt (no Docker available)
if [[ "${DISTRO_FAMILY:-}" == "openwrt" ]]; then
    echo "[mumble] Skipping — Docker not available on OpenWrt"
    exit 0
fi

log() { echo "[mumble] $*"; }

if ! command -v docker &>/dev/null; then
    case "${DISTRO_FAMILY}" in
        debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io ;;
        fedora) dnf install -y docker ;;
        arch)   pacman -S --noconfirm --needed docker ;;
    esac
    systemctl enable docker 2>/dev/null || true
    systemctl start docker || true
fi

mkdir -p /var/lib/mstpistation/mumble

log "Mumble ready to deploy"
