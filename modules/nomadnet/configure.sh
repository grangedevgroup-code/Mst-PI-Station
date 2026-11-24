#!/usr/bin/env bash
set -euo pipefail

MSTPISTATION_DIR="${MSTPISTATION_DIR:-/opt/mstpistation}"
VENV="${MSTPISTATION_DIR}/venv"
NOMADNET_HOME="/var/lib/mstpistation/nomadnet"
NODE_NAME="${NODE_NAME:-mstpistation-node}"
NODE_PROFILE="${NODE_PROFILE:-relay}"

log() { echo "[nomadnet/configure] $*"; }

mkdir -p "${NOMADNET_HOME}/pages" "${NOMADNET_HOME}/storage"
chown -R reticulum:reticulum "${NOMADNET_HOME}" 2>/dev/null || true

# Write NomadNet config
mkdir -p "${NOMADNET_HOME}/.nomadnetwork"
cat > "${NOMADNET_HOME}/.nomadnetwork/config" << CONF
[logging]
  loglevel = 4

[reticulum]
  enable_transport = False
  share_instance = True

[node]
  enable_node = yes
  node_name = ${NODE_NAME}
  announce_interval = 1800

[textui]
  enable_textui = No
CONF

# Write the node's home page
cat > "${NOMADNET_HOME}/pages/index.mu" << PAGE
#!c=Mst-PI-Station Node
> ${NODE_NAME}
> Profile: ${NODE_PROFILE}

This is an Mst-PI-Station communications node providing:

  * Resilient mesh networking
  * Encrypted messaging via LXMF
  * LoRa long-range transport
  * Off-grid field communications

>> How to connect

Connect your Sideband app or NomadNet to this node.
Reticulum address: see node announcements.

>> Status

Uptime: see dashboard at mstpistation.local:8080

>> Mst-PI-Station Project

Resilient mesh communications for field deployments.
PAGE

chown -R reticulum:reticulum "${NOMADNET_HOME}" 2>/dev/null || true

# Restart service
systemctl enable mstpistation-nomadnet 2>/dev/null || true
systemctl restart mstpistation-nomadnet || true

sleep 2
if systemctl is-active mstpistation-nomadnet &>/dev/null; then
    log "NomadNet node running as '${NODE_NAME}'"
else
    log "WARNING: NomadNet not active. Check: journalctl -u mstpistation-nomadnet"
fi

log "NomadNet configuration complete"
