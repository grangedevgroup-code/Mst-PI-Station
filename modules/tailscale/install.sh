#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[tailscale] $*"; }

if command -v tailscale &>/dev/null; then
    log "Tailscale already installed"
    exit 0
fi

case "${DISTRO_FAMILY}" in
    debian)
        curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null || \
        (curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.gpg \
            | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
         echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] \
             https://pkgs.tailscale.com/stable/debian bookworm main" \
             > /etc/apt/sources.list.d/tailscale.list && \
         apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale)
        ;;
    fedora)
        dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo 2>/dev/null || true
        dnf install -y tailscale
        ;;
    arch)
        pacman -S --noconfirm --needed tailscale
        ;;
    *)
        # Universal install script fallback
        curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null || \
            log "WARNING: Install Tailscale manually from https://tailscale.com/download"
        ;;
esac

systemctl enable tailscaled 2>/dev/null || true
systemctl start tailscaled || true
log "Tailscale installed"
