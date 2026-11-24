#!/usr/bin/env bash
set -euo pipefail

log() { echo "[gps/configure] $*"; }

# Auto-detect GPS device
GPS_DEV=""
for candidate in /dev/gps0 /dev/ttyUSB0 /dev/ttyAMA0 /dev/ttyS0 /dev/ttyACM0; do
    [[ -e "${candidate}" ]] && GPS_DEV="${candidate}" && break
done

if [[ -z "${GPS_DEV}" ]]; then
    log "No GPS device found. Connect USB GPS and re-run: mstpistation module enable gps"
    # Still write gpsd config so it auto-starts when device appears
    GPS_DEV="/dev/ttyUSB0"
fi

log "Configuring gpsd for device: ${GPS_DEV}"

# Write gpsd config
cat > /etc/default/gpsd << GPSD
START_DAEMON="true"
GPSD_OPTIONS="-n -b"
DEVICES="${GPS_DEV}"
USBAUTO="true"
GPSD_SOCKET="/var/run/gpsd.sock"
GPSD

# Write gpsd systemd socket activation config
cat > /etc/systemd/system/gpsd.service << SVC
[Unit]
Description=GPS daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/gpsd -n -N -b ${GPS_DEV} /var/run/gpsd.sock
PIDFile=/run/gpsd.pid
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable gpsd 2>/dev/null || true
systemctl restart gpsd || true

sleep 2

if command -v gpsmon &>/dev/null && [[ -e "${GPS_DEV}" ]]; then
    log "GPS daemon running. Test with: cgps or gpsmon"
else
    log "GPS daemon configured. Awaiting device on ${GPS_DEV}"
fi

# Also configure node location update via gpsd
cat > /etc/systemd/system/mstpistation-gps-location.service << LOCSVC
[Unit]
Description=Mst-PI-Station GPS Location Update
After=gpsd.service
Requires=gpsd.service

[Service]
Type=simple
ExecStart=/opt/mstpistation/venv/bin/python3 /opt/mstpistation/modules/gps/location-updater.py
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
LOCSVC

systemctl daemon-reload
systemctl enable mstpistation-gps-location 2>/dev/null || true
systemctl start mstpistation-gps-location 2>/dev/null || true

log "GPS configuration complete"
