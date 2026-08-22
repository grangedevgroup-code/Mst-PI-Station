#!/usr/bin/env bash
set -euo pipefail
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[wireguard] $*"; }

case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard wireguard-tools ;;
    fedora) dnf install -y wireguard-tools ;;
    arch)   pacman -S --noconfirm --needed wireguard-tools ;;
    *)      log "WARNING: Install wireguard-tools manually" ;;
esac

# Generate keypair if not already present
WG_DIR="/etc/aetherium/wireguard"
mkdir -p "${WG_DIR}"
chmod 700 "${WG_DIR}"

if [[ ! -f "${WG_DIR}/private.key" ]]; then
    wg genkey | tee "${WG_DIR}/private.key" | wg pubkey > "${WG_DIR}/public.key"
    chmod 600 "${WG_DIR}/private.key"
    log "Generated WireGuard keypair"
    log "Public key: $(cat "${WG_DIR}/public.key")"
    log "Share the public key with your WireGuard server admin"
else
    log "Existing keypair found. Public key: $(cat "${WG_DIR}/public.key")"
fi

log "WireGuard installation complete"
