#!/usr/bin/env bash
set -euo pipefail
source /etc/aetherium/distro.env 2>/dev/null || DISTRO_FAMILY="debian"
AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
VENV="${AETHERIUM_DIR}/venv"

log() { echo "[gps] $*"; }

case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                gpsd gpsd-clients chrony python3-gps pps-tools ;;
    fedora) dnf install -y gpsd gpsd-clients chrony ;;
    arch)   pacman -S --noconfirm --needed gpsd chrony ;;
    *)      log "WARNING: Install gpsd and chrony manually" ;;
esac

"${VENV}/bin/pip" install --quiet gpsd-py3 2>/dev/null || \
"${VENV}/bin/pip" install --quiet gps3 2>/dev/null || true

# udev rules for common GPS devices
cat > /etc/udev/rules.d/99-aetherium-gps.rules << 'UDEV'
# GPS receiver rules

# u-blox GPS (common, used in many Pi HATs)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1546", ATTRS{idProduct}=="01a8", \
    SYMLINK+="gps0", MODE="0660", GROUP="dialout"

# GlobalTop / PA6H (Adafruit Ultimate GPS)
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", \
    SYMLINK+="gps0", MODE="0660", GROUP="dialout"

# SiRF GPS modules
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
    ENV{ID_MODEL}=="*GPS*", SYMLINK+="gps0", MODE="0660", GROUP="dialout"

# Generic USB GPS
SUBSYSTEM=="tty", ATTRS{idVendor}=="1546", \
    SYMLINK+="gps0", MODE="0660", GROUP="dialout"

# Raspberry Pi PPS GPIO (pulse-per-second)
SUBSYSTEM=="pps", KERNEL=="pps0", MODE="0660", GROUP="dialout"
UDEV

udevadm control --reload-rules 2>/dev/null || true

# Chrony config for GPS-disciplined time
cat > /etc/chrony/conf.d/aetherium-gps.conf << CHRONY
# GPS time source via gpsd
refclock SHM 0 refid GPS precision 1e-1 offset 0.9999 delay 0.2 trust
refclock SHM 2 refid PPS precision 1e-9 prefer

# Allow serving time to local mesh nodes
allow 192.168.0.0/16
allow 10.0.0.0/8
CHRONY

systemctl enable chrony 2>/dev/null || systemctl enable chronyd 2>/dev/null || true
systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true

log "GPS module installed"
log "Supported devices: u-blox, Adafruit Ultimate GPS, SiRF, most USB GPS"
