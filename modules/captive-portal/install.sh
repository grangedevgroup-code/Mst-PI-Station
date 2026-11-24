#!/usr/bin/env bash
set -euo pipefail
source /etc/mstpistation/distro.env 2>/dev/null || DISTRO_FAMILY="debian"

log() { echo "[captive-portal] $*"; }

case "${DISTRO_FAMILY}" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx ;;
    fedora) dnf install -y nginx ;;
    arch)   pacman -S --noconfirm --needed nginx ;;
    *)      log "WARNING: Install nginx manually for ${DISTRO_FAMILY}" ;;
esac

mkdir -p /etc/mstpistation/captive-portal /var/www/mstpistation-portal

# Disable default nginx site
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# nginx site config for captive portal (port 80 only — portal intercept)
cat > /etc/nginx/sites-available/mstpistation-portal << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/mstpistation-portal;
    index index.html;

    # Serve portal page for all requests
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Apple/Android/Windows captive portal detection endpoints
    location /hotspot-detect.html      { return 200 "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"; }
    location /generate_204             { return 204; }
    location /connecttest.txt          { return 200 "Microsoft NCSI"; }
    location /ncsi.txt                 { return 200 "Microsoft NCSI"; }
    location /success.txt              { return 200 "Success\n"; }

    access_log /var/log/nginx/mstpistation-portal-access.log;
    error_log  /var/log/nginx/mstpistation-portal-error.log;
}
NGINX

ln -sf /etc/nginx/sites-available/mstpistation-portal /etc/nginx/sites-enabled/mstpistation-portal 2>/dev/null || \
    cp /etc/nginx/sites-available/mstpistation-portal /etc/nginx/conf.d/mstpistation-portal.conf

log "Captive portal nginx config installed"
