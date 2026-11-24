#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[power] $*"; }

case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            cpufrequtils linux-cpupower 2>/dev/null || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cpufrequtils 2>/dev/null || true
        ;;
    fedora)
        dnf install -y kernel-tools 2>/dev/null || true
        ;;
    arch)
        pacman -S --noconfirm --needed cpupower 2>/dev/null || true
        ;;
esac

# Power management systemd service
cat > /etc/systemd/system/mstpistation-power.service << 'SVC'
[Unit]
Description=Mst-PI-Station Power Management
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /etc/mstpistation/power/apply-power-profile.sh
ExecStop=/bin/bash /etc/mstpistation/power/apply-power-profile.sh restore

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
mkdir -p /etc/mstpistation/power
log "Power management installed"
