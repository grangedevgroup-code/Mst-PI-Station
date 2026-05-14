#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-aetherium}"
AP_INTERFACE="${AP_INTERFACE:-wlan0}"

log() { echo "[avahi/configure] $*"; }

# Configure avahi-daemon: allow on AP/mesh interfaces, not just loopback
cat > /etc/avahi/avahi-daemon.conf << CONF
[server]
host-name=${NODE_NAME}
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=${AP_INTERFACE},bat0,eth0
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

# Service definitions — each Aetherium service gets an mDNS record
# Dashboard
cat > /etc/avahi/services/aetherium-dashboard.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Aetherium Dashboard (%h)</name>
  <service>
    <type>_http._tcp</type>
    <port>8080</port>
    <txt-record>path=/</txt-record>
    <txt-record>description=Aetherium mesh node dashboard</txt-record>
  </service>
</service-group>
XML

# Syncthing
cat > /etc/avahi/services/aetherium-syncthing.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Aetherium Syncthing (%h)</name>
  <service>
    <type>_http._tcp</type>
    <port>8384</port>
    <txt-record>path=/</txt-record>
    <txt-record>description=Syncthing mesh file sync</txt-record>
  </service>
</service-group>
XML

# Reticulum TCP interface
cat > /etc/avahi/services/aetherium-reticulum.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Aetherium Reticulum (%h)</name>
  <service>
    <type>_reticulum._tcp</type>
    <port>4242</port>
    <txt-record>description=Reticulum TCP interface</txt-record>
  </service>
</service-group>
XML

# Gitea (only if running)
if systemctl is-active aetherium-gitea &>/dev/null || docker ps 2>/dev/null | grep -q aetherium-gitea; then
cat > /etc/avahi/services/aetherium-gitea.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Aetherium Gitea (%h)</name>
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
cat > /etc/avahi/services/aetherium-mumble.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Aetherium Mumble (%h)</name>
  <service>
    <type>_mumble._tcp</type>
    <port>64738</port>
    <txt-record>description=Aetherium mesh voice server</txt-record>
  </service>
</service-group>
XML

systemctl restart avahi-daemon 2>/dev/null || true

log "Avahi mDNS configured"
log "Node discoverable as: ${NODE_NAME}.local"
log "Services announced: dashboard, syncthing, reticulum, gitea, mumble"
