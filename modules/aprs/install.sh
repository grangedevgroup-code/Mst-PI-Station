#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"

log() { echo "[aprs] $*"; }

case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq direwolf 2>/dev/null || {
            # Build from source if not in repos
            log "direwolf not in repos, building from source..."
            apt-get install -y -qq cmake build-essential libasound2-dev libhamlib-dev
            tmpdir=$(mktemp -d)
            git clone --depth=1 https://github.com/wb2osz/direwolf "${tmpdir}/direwolf"
            cmake -S "${tmpdir}/direwolf" -B "${tmpdir}/build"
            cmake --build "${tmpdir}/build" --parallel
            cmake --install "${tmpdir}/build"
            rm -rf "${tmpdir}"
        }
        ;;
    fedora) dnf install -y direwolf 2>/dev/null || log "Install direwolf manually" ;;
    arch)   pacman -S --noconfirm --needed direwolf 2>/dev/null || log "Install direwolf manually" ;;
    *)      log "WARNING: Install direwolf manually from https://github.com/wb2osz/direwolf" ;;
esac

if command -v direwolf &>/dev/null; then
    log "direwolf $(direwolf --version 2>&1 | head -1) installed"
else
    log "WARNING: direwolf not found. APRS will not function."
fi

mkdir -p /etc/mstpistation/aprs /var/log/mstpistation/aprs /var/lib/mstpistation/aprs

# Install systemd service
cat > /etc/systemd/system/mstpistation-direwolf.service << SVC
[Unit]
Description=Mst-PI-Station Direwolf APRS TNC
After=sound.target

[Service]
Type=simple
ExecStart=/usr/bin/direwolf -c /etc/mstpistation/aprs/direwolf.conf -t 0 -a 0
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mstpistation-direwolf
User=root

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
log "APRS/Direwolf installed"
