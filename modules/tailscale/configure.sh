#!/usr/bin/env bash
set -euo pipefail

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-${NODE_NAME:-mstpistation}}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-0}"   # Advertise as exit node
TAILSCALE_SUBNET="${TAILSCALE_SUBNET:-}"          # e.g. 192.168.100.0/24 for mesh subnet

log() { echo "[tailscale/configure] $*"; }

# Load auth key from mstpistation.yaml if not in env
if [[ -z "${TAILSCALE_AUTH_KEY}" ]] && [[ -f /etc/mstpistation/mstpistation.yaml ]]; then
    TAILSCALE_AUTH_KEY=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
print(cfg.get('tailscale', {}).get('auth_key', ''))
" 2>/dev/null || echo "")
fi

if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
    log "WARNING: No tailscale.auth_key in mstpistation.yaml"
    log "Run manually: tailscale up --hostname ${TAILSCALE_HOSTNAME}"
    log "Or set tailscale.auth_key in /etc/mstpistation/mstpistation.yaml and re-deploy"
    exit 0
fi

# Build tailscale up args
ARGS="--auth-key ${TAILSCALE_AUTH_KEY} --hostname ${TAILSCALE_HOSTNAME} --accept-dns=false"

if [[ "${TAILSCALE_EXIT_NODE}" == "1" ]]; then
    ARGS="${ARGS} --advertise-exit-node"
fi

if [[ -n "${TAILSCALE_SUBNET}" ]]; then
    ARGS="${ARGS} --advertise-routes=${TAILSCALE_SUBNET}"
fi

# Enable IP forwarding for subnet routing
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null || true

tailscale up ${ARGS} 2>/dev/null && \
    log "Tailscale connected — IP: $(tailscale ip -4 2>/dev/null || echo 'pending')" || \
    log "WARNING: tailscale up failed — check auth key"
