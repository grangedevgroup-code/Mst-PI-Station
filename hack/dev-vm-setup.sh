#!/usr/bin/env bash
# Mst-PI-Station dev VM setup — spins up a QEMU ARM64 VM for testing
# Requires: qemu-system-aarch64, qemu-utils, wget
set -euo pipefail

IMG_URL="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-latest"
IMG_FILE="/tmp/mstpistation-dev-vm.img"
VM_DISK="/tmp/mstpistation-dev.qcow2"
VM_PORT=2222

log()  { echo "[dev-vm] $*"; }

if ! command -v qemu-system-aarch64 &>/dev/null; then
    log "Install qemu-system-arm first:"
    log "  Ubuntu/Debian: sudo apt install qemu-system-arm qemu-utils"
    exit 1
fi

if [[ ! -f "${VM_DISK}" ]]; then
    log "Downloading Raspberry Pi OS Lite ARM64..."
    wget -q -O "${IMG_FILE}.xz" "${IMG_URL}"
    xz -d "${IMG_FILE}.xz"
    qemu-img convert -f raw -O qcow2 "${IMG_FILE}" "${VM_DISK}"
    qemu-img resize "${VM_DISK}" +4G
    log "VM disk ready at ${VM_DISK}"
fi

log "Starting QEMU ARM64 VM..."
log "SSH: ssh -p ${VM_PORT} pi@localhost (password: raspberry)"
log "To install Mst-PI-Station inside VM: sudo bash /vagrant/install.sh"

qemu-system-aarch64 \
    -machine raspi3b \
    -cpu cortex-a53 \
    -m 1G \
    -smp 4 \
    -drive "file=${VM_DISK},format=qcow2" \
    -netdev "user,id=net0,hostfwd=tcp::${VM_PORT}-:22" \
    -device usb-net,netdev=net0 \
    -nographic \
    -serial mon:stdio
