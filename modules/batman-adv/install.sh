#!/usr/bin/env bash
set -euo pipefail

source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"
AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"

log() { echo "[batman-adv] $*"; }

# Install batctl and batman-adv kernel module
case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            batctl batman-adv-dkms || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            batctl linux-modules-extra-$(uname -r) 2>/dev/null || true
        ;;
    fedora)
        dnf install -y batctl kmod-batman-adv 2>/dev/null || \
        dnf install -y batctl 2>/dev/null || true
        ;;
    arch)
        pacman -S --noconfirm --needed batctl 2>/dev/null || true
        ;;
    *)
        log "WARNING: Auto-install not supported for ${DISTRO_FAMILY}. Install batctl manually."
        ;;
esac

# Try to compile from source if module not available
if ! modinfo batman-adv &>/dev/null 2>&1; then
    log "batman-adv kernel module not found, attempting DKMS build..."
    local_src="${AETHERIUM_DIR}/SourceDependencies/batman-adv-main"
    if [[ -d "${local_src}" ]] && command -v make &>/dev/null; then
        # Install build deps
        case "${DISTRO_FAMILY}" in
            debian)
                apt-get install -y -qq dkms linux-headers-$(uname -r) build-essential 2>/dev/null || true
                ;;
            fedora)
                dnf install -y dkms kernel-devel gcc 2>/dev/null || true
                ;;
        esac
        pushd "${local_src}" > /dev/null
        make 2>/dev/null && make install 2>/dev/null || log "Source build failed — LoRa mesh may not work"
        popd > /dev/null
    fi
fi

# Load module
modprobe batman-adv 2>/dev/null && log "batman-adv module loaded" || \
    log "WARNING: batman-adv module could not be loaded"

# Persist module loading
if [[ ! -f /etc/modules-load.d/batman-adv.conf ]]; then
    echo "batman-adv" > /etc/modules-load.d/batman-adv.conf
    log "batman-adv added to modules-load.d"
fi

# Install systemd service
if command -v systemctl &>/dev/null; then
    install -m644 "${MODULE_DIR}/systemd/batman-adv.service" /etc/systemd/system/
    systemctl daemon-reload
fi

# Verify batctl
if command -v batctl &>/dev/null; then
    log "batctl $(batctl -v 2>/dev/null | head -1) ready"
else
    log "WARNING: batctl not found — install manually"
fi

log "batman-adv installation complete"
