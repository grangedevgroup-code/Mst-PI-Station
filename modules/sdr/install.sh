#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"
MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"

log() { echo "[sdr] $*"; }

# rtl-sdr kernel module blacklist (prevents default DVB-T driver from grabbing device)
cat > /etc/modprobe.d/rtl-sdr-blacklist.conf << 'EOF'
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF

case "${DISTRO_FAMILY}" in
    debian)
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            rtl-sdr librtlsdr-dev rtl-433 \
            2>/dev/null || true
        # dump1090 from package if available, otherwise build
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dump1090-fa \
            2>/dev/null || DUMP1090_BUILD=1
        ;;
    fedora)
        dnf install -y rtl-sdr rtl-sdr-devel rtl_433 2>/dev/null || true
        DUMP1090_BUILD=1
        ;;
    arch)
        pacman -S --noconfirm --needed rtl-sdr rtl_433 2>/dev/null || true
        DUMP1090_BUILD=1
        ;;
    *)
        log "WARNING: Manual rtl-sdr installation required for ${DISTRO_FAMILY}"
        ;;
esac

DUMP1090_BUILD="${DUMP1090_BUILD:-0}"

if [[ "${DUMP1090_BUILD}" == "1" ]] && ! command -v dump1090 &>/dev/null; then
    log "Building dump1090-fa from source..."
    if ! command -v git &>/dev/null; then
        case "${DISTRO_FAMILY}" in
            debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git build-essential pkg-config ;;
            fedora) dnf install -y git gcc make pkgconfig ;;
            arch)   pacman -S --noconfirm --needed git base-devel ;;
        esac
    fi
    TMP_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/flightaware/dump1090 "${TMP_DIR}/dump1090" 2>/dev/null && \
    make -C "${TMP_DIR}/dump1090" -j"$(nproc)" 2>/dev/null && \
    install -m 755 "${TMP_DIR}/dump1090/dump1090" /usr/local/bin/dump1090 && \
    rm -rf "${TMP_DIR}" || \
    log "WARNING: dump1090 build failed — ADS-B tracking will be unavailable"
fi

# rtl_433 config directory
mkdir -p /etc/mstpistation/sdr /var/log/mstpistation/sdr

# udev rule for RTL-SDR dongles
cat > /etc/udev/rules.d/90-rtlsdr.rules << 'EOF'
# RTL2832U-based SDR dongles
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0664", GROUP="plugdev", SYMLINK+="rtlsdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0664", GROUP="plugdev", SYMLINK+="rtlsdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2840", MODE="0664", GROUP="plugdev", SYMLINK+="rtlsdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2841", MODE="0664", GROUP="plugdev", SYMLINK+="rtlsdr"
EOF
udevadm control --reload-rules 2>/dev/null || true

# Add mstpistation user to plugdev
usermod -aG plugdev mstpistation 2>/dev/null || true

# rtl_433 systemd service
cat > /etc/systemd/system/mstpistation-rtl433.service << 'SVC'
[Unit]
Description=Mst-PI-Station rtl_433 IoT/Weather Decoder
After=network.target
ConditionPathExists=/dev/rtlsdr

[Service]
Type=simple
User=mstpistation
ExecStart=/bin/bash /etc/mstpistation/sdr/rtl433-start.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

# dump1090 systemd service
cat > /etc/systemd/system/mstpistation-dump1090.service << 'SVC'
[Unit]
Description=Mst-PI-Station dump1090 ADS-B Receiver
After=network.target
ConditionPathExists=/dev/rtlsdr

[Service]
Type=simple
User=mstpistation
ExecStart=/bin/bash /etc/mstpistation/sdr/dump1090-start.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
log "SDR tools installed"
