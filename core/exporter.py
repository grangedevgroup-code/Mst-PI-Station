#!/usr/bin/env python3
"""
Mst-PI-Station Custom Prometheus Exporter
Exposes batman-adv, Reticulum, GPS, SDR, and node-specific metrics.
Runs on port 9200.
"""

import os
import sys
import re
import time
import json
import subprocess
from pathlib import Path

MSTPISTATION_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(MSTPISTATION_DIR))

try:
    from prometheus_client import start_http_server, Gauge, Counter, Info, Enum
    from prometheus_client import REGISTRY, PROCESS_COLLECTOR, PLATFORM_COLLECTOR
    REGISTRY.unregister(PROCESS_COLLECTOR)
    REGISTRY.unregister(PLATFORM_COLLECTOR)
except ImportError:
    print("prometheus_client not installed. Run: pip install prometheus_client", file=sys.stderr)
    sys.exit(1)

PORT = 9200
INTERVAL = 15  # seconds

# ── Metric definitions ────────────────────────────────────────────────────────

# Node identity
node_info = Info("mstpistation_node", "Mst-PI-Station node information")

# Batman-adv mesh
batman_peers = Gauge("mstpistation_batman_peers_total", "Number of batman-adv mesh neighbors")
batman_gateways = Gauge("mstpistation_batman_gateways_total", "Number of batman-adv gateways visible")

# Reticulum
rns_interfaces_up = Gauge("mstpistation_rns_interfaces_up", "Reticulum interfaces that are active")
rns_announced_dests = Gauge("mstpistation_rns_announced_destinations", "Reticulum announced destinations known")

# Services
service_up = Gauge("mstpistation_service_up", "Service health (1=active, 0=down)", ["service"])

# Wi-Fi
wifi_signal = Gauge("mstpistation_wifi_signal_dbm", "Wi-Fi signal strength in dBm", ["interface"])
wifi_clients = Gauge("mstpistation_wifi_clients_total", "Number of associated Wi-Fi clients", ["interface"])

# LTE
lte_signal = Gauge("mstpistation_lte_signal_dbm", "LTE signal strength (RSSI)", ["modem"])
lte_connected = Gauge("mstpistation_lte_connected", "LTE data connection status (1=up)")

# GPS
gps_fix = Gauge("mstpistation_gps_fix", "GPS fix quality (0=none, 1=2D, 2=3D)")
gps_satellites = Gauge("mstpistation_gps_satellites", "GPS satellites in use")
gps_latitude = Gauge("mstpistation_gps_latitude_deg", "GPS latitude in degrees")
gps_longitude = Gauge("mstpistation_gps_longitude_deg", "GPS longitude in degrees")
gps_altitude = Gauge("mstpistation_gps_altitude_m", "GPS altitude in meters")

# Temperature sensors
cpu_temp = Gauge("mstpistation_cpu_temp_celsius", "CPU temperature in Celsius")

# Power
battery_voltage = Gauge("mstpistation_battery_voltage_v", "Battery voltage in volts")
battery_percent = Gauge("mstpistation_battery_percent", "Battery charge percentage")


# ── Collection functions ──────────────────────────────────────────────────────

def collect_node_info():
    try:
        from core.config import Config
        from core.hardware import Hardware
        cfg = Config()
        hw = Hardware()
        node_info.info({
            "name": cfg.get("node.name", "unknown"),
            "profile": cfg.get("node.profile", "unknown"),
            "model": hw.model,
            "arch": hw.arch,
        })
    except Exception:
        pass


def collect_batman():
    try:
        r = subprocess.run(["batctl", "n", "-H"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            lines = [l for l in r.stdout.strip().split("\n") if l.strip()]
            batman_peers.set(len(lines))

        r2 = subprocess.run(["batctl", "gwl", "-H"],
                            capture_output=True, text=True, timeout=5)
        if r2.returncode == 0:
            gws = [l for l in r2.stdout.strip().split("\n") if l.strip()]
            batman_gateways.set(len(gws))
    except Exception:
        batman_peers.set(0)
        batman_gateways.set(0)


def collect_services():
    watched = [
        "reticulum", "mstpistation-hostapd", "batman-adv",
        "dnsmasq", "mstpistation-agent", "mstpistation-lxmf",
        "mstpistation-nomadnet", "mstpistation-dashboard",
    ]
    for svc in watched:
        try:
            r = subprocess.run(["systemctl", "is-active", svc],
                               capture_output=True, text=True, timeout=3)
            val = 1 if r.stdout.strip() == "active" else 0
        except Exception:
            val = 0
        service_up.labels(service=svc).set(val)


def collect_wifi():
    try:
        for entry in Path("/sys/class/net").iterdir():
            name = entry.name
            if not (entry / "wireless").exists():
                continue

            # Signal via iw
            r = subprocess.run(["iw", "dev", name, "link"],
                               capture_output=True, text=True, timeout=3)
            for line in r.stdout.split("\n"):
                m = re.search(r"signal:\s*(-?\d+)\s*dBm", line)
                if m:
                    wifi_signal.labels(interface=name).set(int(m.group(1)))

            # Client count via iw station dump (AP mode)
            r2 = subprocess.run(["iw", "dev", name, "station", "dump"],
                                capture_output=True, text=True, timeout=3)
            clients = r2.stdout.count("Station ")
            wifi_clients.labels(interface=name).set(clients)
    except Exception:
        pass


def collect_lte():
    try:
        r = subprocess.run(["mmcli", "-L"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode != 0 or not r.stdout.strip():
            lte_connected.set(0)
            return

        # Get first modem
        m = re.search(r"Modem/(\d+)", r.stdout)
        if not m:
            return
        idx = m.group(1)

        r2 = subprocess.run(["mmcli", "-m", idx, "-J"],
                            capture_output=True, text=True, timeout=5)
        if r2.returncode == 0:
            data = json.loads(r2.stdout)
            modem = data.get("modem", {})
            state = modem.get("generic", {}).get("state", "")
            lte_connected.set(1 if state == "connected" else 0)

            # Signal
            signal_data = modem.get("signal", {}).get("lte", {})
            rssi = signal_data.get("rssi")
            if rssi:
                lte_signal.labels(modem=idx).set(float(rssi))
    except Exception:
        lte_connected.set(0)


def collect_gps():
    """Read GPS data from gpsd socket."""
    try:
        import socket, json
        with socket.create_connection(("localhost", 2947), timeout=3) as s:
            s.sendall(b'?WATCH={"enable":true,"json":true}\n')
            s.sendall(b'?POLL;\n')
            data = s.recv(4096).decode("utf-8", errors="replace")

        for line in data.split("\n"):
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("class") == "TPV":
                mode = obj.get("mode", 0)
                gps_fix.set(mode - 1 if mode > 1 else 0)
                if "lat" in obj:
                    gps_latitude.set(obj["lat"])
                if "lon" in obj:
                    gps_longitude.set(obj["lon"])
                if "alt" in obj:
                    gps_altitude.set(obj["alt"])
            elif obj.get("class") == "SKY":
                used = sum(1 for s in obj.get("satellites", []) if s.get("used"))
                gps_satellites.set(used)
    except Exception:
        pass


def collect_temp():
    for path in ["/sys/class/thermal/thermal_zone0/temp",
                 "/sys/class/hwmon/hwmon0/temp1_input"]:
        try:
            raw = int(Path(path).read_text().strip())
            cpu_temp.set(raw / 1000)
            return
        except Exception:
            continue


def collect_battery():
    """Read battery from UPS HAT or INA219-style ADC if available."""
    # Check common battery HAT locations
    for path in ["/sys/class/power_supply/BAT0",
                 "/sys/class/power_supply/battery",
                 "/sys/class/power_supply/ups-battery"]:
        p = Path(path)
        if not p.exists():
            continue
        try:
            cap_file = p / "capacity"
            volt_file = p / "voltage_now"
            if cap_file.exists():
                battery_percent.set(int(cap_file.read_text().strip()))
            if volt_file.exists():
                uv = int(volt_file.read_text().strip())
                battery_voltage.set(uv / 1_000_000)  # µV → V
            return
        except Exception:
            continue


# ── Main loop ─────────────────────────────────────────────────────────────────

def collect_all():
    collect_node_info()
    collect_batman()
    collect_services()
    collect_wifi()
    collect_lte()
    collect_gps()
    collect_temp()
    collect_battery()


def main():
    start_http_server(PORT)
    print(f"Mst-PI-Station exporter running on :{PORT}")

    while True:
        try:
            collect_all()
        except Exception as e:
            print(f"Collection error: {e}", file=sys.stderr)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
