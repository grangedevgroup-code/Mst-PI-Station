#!/usr/bin/env bash
set -euo pipefail

AETHERIUM_DIR="${AETHERIUM_DIR:-/opt/aetherium}"
RNODE_PORT="${RNODE_PORT:-}"
RNODE_FREQ="${RNODE_FREQ:-915000000}"

log() { echo "[rnode/configure] $*"; }

# Auto-detect port if not set
if [[ -z "${RNODE_PORT}" ]]; then
    if [[ -e /dev/rnode0 ]]; then
        RNODE_PORT="/dev/rnode0"
    elif [[ -e /dev/ttyUSB0 ]]; then
        RNODE_PORT="/dev/ttyUSB0"
    elif [[ -e /dev/ttyACM0 ]]; then
        RNODE_PORT="/dev/ttyACM0"
    fi
fi

if [[ -z "${RNODE_PORT}" ]]; then
    log "No RNode detected. Skipping RNode configuration."
    log "When you connect an RNode, run: aetherium module enable rnode"
    exit 0
fi

log "Configuring RNode on ${RNODE_PORT}"

# Check if RNode needs firmware flashing (rnodeconf --autoinstall)
RNODE_VENV="${AETHERIUM_DIR}/venv/bin/rnodeconf"
if [[ -x "${RNODE_VENV}" ]]; then
    # Check RNode status
    if "${RNODE_VENV}" "${RNODE_PORT}" --info 2>/dev/null | grep -q "Reticulum"; then
        log "RNode is already configured with Reticulum firmware"
    else
        log "RNode may need firmware. Run manually:"
        log "  rnodeconf ${RNODE_PORT} --autoinstall"
        log "Or if already an RNode: rnodeconf ${RNODE_PORT} --info"
    fi
fi

# Update the site config with detected port
python3 << PYEOF
import yaml, sys
config_file = "/etc/aetherium/aetherium.yaml"
try:
    with open(config_file) as f:
        cfg = yaml.safe_load(f) or {}
    cfg.setdefault("rnode", {})["port"] = "${RNODE_PORT}"
    cfg.setdefault("rnode", {})["frequency"] = int("${RNODE_FREQ}")
    with open(config_file, "w") as f:
        yaml.dump(cfg, f, default_flow_style=False)
    print(f"Updated {config_file}: rnode.port = ${RNODE_PORT}")
except Exception as e:
    print(f"Could not update config: {e}", file=sys.stderr)
PYEOF

# Restart Reticulum to pick up the new RNode interface
systemctl restart reticulum 2>/dev/null || true
log "Reticulum restarted to activate RNode interface"
log "RNode configuration complete (port=${RNODE_PORT}, freq=${RNODE_FREQ})"
