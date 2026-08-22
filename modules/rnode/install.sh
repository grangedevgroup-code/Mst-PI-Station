#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[rnode] $*"; }

# Install rnodeconf — the RNode configuration tool
"${VENV}/bin/pip" install --quiet rnodeconf 2>/dev/null || true

# Also need pyserial for RNode communication
"${VENV}/bin/pip" install --quiet pyserial 2>/dev/null || true

# Add user to dialout group for serial access
SUDO_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
if [[ "${SUDO_USER}" != "root" ]]; then
    usermod -aG dialout "${SUDO_USER}" 2>/dev/null || true
    log "Added ${SUDO_USER} to dialout group"
fi
usermod -aG dialout reticulum 2>/dev/null || true

# udev rules for common RNode-compatible devices
cat > /etc/udev/rules.d/99-aetherium-rnode.rules << 'UDEV'
# Aetherium RNode / LoRa interface rules

# CH340 USB-Serial (many RNode devices)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", \
    SYMLINK+="rnode0", MODE="0660", GROUP="dialout"

# CP2102 USB-Serial (Heltec, TTGO)
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", \
    SYMLINK+="rnode0", MODE="0660", GROUP="dialout"

# FTDI FT232 (generic)
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
    SYMLINK+="rnode0", MODE="0660", GROUP="dialout"

# Microchip MCP2221
SUBSYSTEM=="tty", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="00dd", \
    SYMLINK+="rnode0", MODE="0660", GROUP="dialout"
UDEV

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

log "RNode tools installed"
if ls /dev/rnode* &>/dev/null 2>&1; then
    log "RNode detected at: $(ls /dev/rnode*)"
elif ls /dev/ttyUSB* &>/dev/null 2>&1; then
    log "Serial device detected: $(ls /dev/ttyUSB*) — may be RNode"
else
    log "No RNode detected. Connect USB RNode and run: rnodeconf --autoinstall"
fi
