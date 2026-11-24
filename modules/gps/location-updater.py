#!/usr/bin/env python3
"""
Mst-PI-Station GPS Location Updater
Reads GPS position and writes to /var/lib/mstpistation/location.json
Also announces position via Reticulum if enabled.
"""

import os, sys, time, json, socket, logging
from pathlib import Path

log = logging.getLogger("gps-location")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

LOCATION_FILE = Path("/var/lib/mstpistation/location.json")
UPDATE_INTERVAL = 10  # seconds


def read_gpsd():
    """Read current position from gpsd."""
    try:
        with socket.create_connection(("localhost", 2947), timeout=5) as s:
            s.sendall(b'?WATCH={"enable":true,"json":true}\n')
            time.sleep(0.5)
            s.sendall(b'?POLL;\n')
            raw = b""
            s.settimeout(3)
            try:
                while True:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    raw += chunk
            except socket.timeout:
                pass

        loc = {"fix": 0, "lat": None, "lon": None, "alt": None,
               "speed": None, "track": None, "satellites": 0,
               "timestamp": None}

        for line in raw.decode("utf-8", errors="replace").split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            cls = obj.get("class", "")
            if cls == "TPV":
                mode = obj.get("mode", 0)
                loc["fix"] = max(0, mode - 1)
                loc["timestamp"] = obj.get("time")
                for k in ("lat", "lon", "alt", "speed", "track"):
                    if k in obj:
                        loc[k] = obj[k]
            elif cls == "SKY":
                loc["satellites"] = sum(1 for sv in obj.get("satellites", []) if sv.get("used"))

        return loc
    except Exception as e:
        log.debug(f"gpsd read error: {e}")
        return None


def main():
    log.info("GPS location updater starting")
    last_valid = None

    while True:
        loc = read_gpsd()
        if loc:
            loc["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            LOCATION_FILE.parent.mkdir(parents=True, exist_ok=True)
            LOCATION_FILE.write_text(json.dumps(loc, indent=2))

            if loc["fix"] > 0 and loc["lat"]:
                if last_valid != (loc["lat"], loc["lon"]):
                    log.info(f"GPS fix: {loc['lat']:.5f}, {loc['lon']:.5f} "
                             f"alt={loc.get('alt', '?')}m sats={loc['satellites']}")
                    last_valid = (loc["lat"], loc["lon"])
            else:
                log.debug(f"No GPS fix (satellites: {loc.get('satellites', 0)})")

        time.sleep(UPDATE_INTERVAL)


if __name__ == "__main__":
    main()
