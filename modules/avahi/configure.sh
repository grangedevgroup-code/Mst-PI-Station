#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || echo mstpistation)}"
AP_INTERFACE="${AP_INTERFACE:-wlan0}"
MESH_INTERFACE="${MESH_INTERFACE:-}"

log() { echo "[avahi/configure] $*"; }

# Configure avahi-daemon: allow on AP/mesh interfaces, not just loopback
cat > /etc/avahi/avahi-daemon.conf << CONF
[server]
host-name=${NODE_NAME}
domain-name=local
use-ipv4=yes
use-ipv6=no
# Dynamically build interface list from deployed configuration
AVAHI_ALLOW=$(python3 -c "
ifaces = ['${AP_INTERFACE}', 'bat0', 'eth0']
mesh = '${MESH_INTERFACE}'
if mesh and mesh not in ifaces:
    ifaces.append(mesh)
# Add any ethernet interfaces that are up
import os
for name in os.listdir('/sys/class/net'):
    if name.startswith(('eth','en')) and name not in ifaces:
        try:
            state = open(f'/sys/class/net/{name}/operstate').read().strip()
            if state in ('up','unknown'):
                ifaces.append(name)
        except Exception:
            pass
print(','.join(ifaces))
" 2>/dev/null || echo "${AP_INTERFACE},bat0,eth0")
allow-interfaces=${AVAHI_ALLOW}
deny-interfaces=tun0,tailscale0
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=no

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no
publish-domain=yes

[reflector]
enable-reflector=no

[rlimits]
rlimit-nofile=768
CONF

# Service definitions — each Mst-PI-Station service gets an mDNS record
# Dashboard
cat > /etc/avahi/services/mstpistation-dashboard.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Mst-PI-Station Dashboard (%h)</name>
  <service>
    <type>_http._tcp</type>
    <port>8080</port>
    <txt-record>path=/</txt-record>
    <txt-record>description=Mst-PI-Station mesh node dashboard</txt-record>
  </service>
</service-group>
XML

# Syncthing
cat > /etc/avahi/services/mstpistation-syncthing.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Mst-PI-Station Syncthing (%h)</name>
  <service>
    <type>_http._tcp</type>
    <port>8384</port>
    <txt-record>path=/</txt-record>
    <txt-record>description=Syncthing mesh file sync</txt-record>
  </service>
</service-group>
XML

# Reticulum TCP interface
cat > /etc/avahi/services/mstpistation-reticulum.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Mst-PI-Station Reticulum (%h)</name>
  <service>
    <type>_reticulum._tcp</type>
    <port>4242</port>
    <txt-record>description=Reticulum TCP interface</txt-record>
  </service>
</service-group>
XML

# Gitea (only if running)
if systemctl is-active mstpistation-gitea &>/dev/null || docker ps 2>/dev/null | grep -q mstpistation-gitea; then
cat > /etc/avahi/services/mstpistation-gitea.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Mst-PI-Station Gitea (%h)</name>
  <service>
    <type>_http._tcp</type>
    <port>3000</port>
    <txt-record>path=/</txt-record>
    <txt-record>description=Gitea git server</txt-record>
  </service>
</service-group>
XML
fi

# Mumble VoIP
cat > /etc/avahi/services/mstpistation-mumble.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Mst-PI-Station Mumble (%h)</name>
  <service>
    <type>_mumble._tcp</type>
    <port>64738</port>
    <txt-record>description=Mst-PI-Station mesh voice server</txt-record>
  </service>
</service-group>
XML

systemctl restart avahi-daemon 2>/dev/null || true

log "Avahi mDNS configured"
log "Node discoverable as: ${NODE_NAME}.local"
log "Services announced: dashboard, syncthing, reticulum, gitea, mumble"
