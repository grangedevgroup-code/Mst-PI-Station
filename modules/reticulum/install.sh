#!/usr/bin/env bash
# Reticulum installation module
set -euo pipefail

source /etc/aetherium/distro.env 2>/dev/null || true

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
RNS_SOURCE="${AETHERIUM_DIR}/SourceDependencies/Reticulum-1.2.5"
VENV="${AETHERIUM_DIR}/venv"
RNS_USER="reticulum"
RNS_HOME="/var/lib/reticulum"

log()  { echo "[reticulum] $*"; }
err()  { echo "[reticulum] ERROR: $*" >&2; }

# Create reticulum system user
if ! id "${RNS_USER}" &>/dev/null; then
    useradd --system --no-create-home --home-dir "${RNS_HOME}" \
            --shell /usr/sbin/nologin \
            --comment "Reticulum Network Stack" \
            "${RNS_USER}"
    log "Created user ${RNS_USER}"
fi

mkdir -p "${RNS_HOME}"
chown "${RNS_USER}:${RNS_USER}" "${RNS_HOME}"

# Install from local source if available, otherwise pip
if [[ -d "${RNS_SOURCE}" ]]; then
    log "Installing Reticulum from local source ${RNS_SOURCE}"
    "${VENV}/bin/pip" install --quiet -e "${RNS_SOURCE}"
else
    log "Installing Reticulum from PyPI"
    "${VENV}/bin/pip" install --quiet rns
fi

# Verify installation
if "${VENV}/bin/python3" -c "import RNS; print('RNS', RNS.__version__)" 2>/dev/null; then
    log "Reticulum installed successfully"
else
    err "Reticulum installation verification failed"
    exit 1
fi

# Install systemd service
if command -v systemctl &>/dev/null; then
    install -m644 "${MODULE_DIR}/systemd/reticulum.service" /etc/systemd/system/
    systemctl daemon-reload
    log "Systemd service installed"
fi

log "Reticulum installation complete"
