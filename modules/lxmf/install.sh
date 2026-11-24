#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
LXMF_SOURCE="${MSTPISTATION_DIR}/SourceDependencies/LXMF-0.9.6"

log() { echo "[lxmf] $*"; }

if [[ -d "${LXMF_SOURCE}" ]]; then
    log "Installing LXMF from local source"
    "${VENV}/bin/pip" install --quiet -e "${LXMF_SOURCE}"
else
    log "Installing LXMF from PyPI"
    "${VENV}/bin/pip" install --quiet lxmf
fi

"${VENV}/bin/python3" -c "import LXMF; print('LXMF', LXMF.__version__)" || {
    echo "[lxmf] ERROR: LXMF installation failed"
    exit 1
}

mkdir -p /var/lib/mstpistation/lxmf
useradd --system --no-create-home --home-dir /var/lib/mstpistation/lxmf \
        --shell /usr/sbin/nologin reticulum 2>/dev/null || true
chown reticulum:reticulum /var/lib/mstpistation/lxmf

if command -v systemctl &>/dev/null; then
    install -m644 "${MODULE_DIR}/systemd/mstpistation-lxmf.service" /etc/systemd/system/
    systemctl daemon-reload
fi

log "LXMF installed"
