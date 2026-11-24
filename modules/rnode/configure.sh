#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
RNODE_PORT="${RNODE_PORT:-}"
REGULATORY_DOMAIN="${REGULATORY_DOMAIN:-}"

# Auto-detect regional LoRa frequency if not explicitly set
if [[ -z "${RNODE_FREQ:-}" ]]; then
    if [[ -z "${REGULATORY_DOMAIN}" ]]; then
        TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "")
        case "${TZ}" in
            America/*) REGULATORY_DOMAIN="US" ;;
            Australia/*|Pacific/Auckland) REGULATORY_DOMAIN="AU" ;;
            Asia/Tokyo) REGULATORY_DOMAIN="JP" ;;
            Asia/Shanghai|Asia/Beijing) REGULATORY_DOMAIN="CN" ;;
            *) REGULATORY_DOMAIN="DE" ;;
        esac
    fi
    case "${REGULATORY_DOMAIN}" in
        US|CA|MX|BR|AU|NZ|AR|CL|CO) RNODE_FREQ="915000000" ;;
        JP|KR)                        RNODE_FREQ="920000000" ;;
        CN)                           RNODE_FREQ="470000000" ;;
        *)                            RNODE_FREQ="868000000" ;;
    esac
    log "Auto-detected LoRa frequency: ${RNODE_FREQ} Hz (region: ${REGULATORY_DOMAIN})"
fi

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
    log "When you connect an RNode, run: mstpistation module enable rnode"
    exit 0
fi

log "Configuring RNode on ${RNODE_PORT}"

# Check if RNode needs firmware flashing (rnodeconf --autoinstall)
RNODE_VENV="${MSTPISTATION_DIR}/venv/bin/rnodeconf"
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
config_file = "/etc/mstpistation/mstpistation.yaml"
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
