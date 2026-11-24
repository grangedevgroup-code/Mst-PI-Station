#!/usr/bin/env python3
"""
Mst-PI-Station Agent — background health monitor and watchdog daemon.
Runs as mstpistation-agent.service
"""

import os
import sys
import json
import time
import signal
import logging
import subprocess
import threading
from pathlib import Path
from typing import Dict, Any

# Ensure we can import mstpistation core
MSTPISTATION_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(MSTPISTATION_DIR))

from core.config import Config
from core.hardware import Hardware

# Paths
STATUS_FILE = Path("/var/run/mstpistation/status.json")
LOG_FILE = Path("/var/log/mstpistation/agent.log")
PEERS_FILE = Path("/var/lib/mstpistation/peers.json")
PID_FILE = Path("/var/run/mstpistation/agent.pid")

# Timing
HEALTH_CHECK_INTERVAL = 30       # seconds between health checks
PEER_DISCOVERY_INTERVAL = 120    # seconds between peer scans
FAILOVER_CHECK_INTERVAL = 15     # seconds between failover checks
RESTART_BACKOFF_BASE = 10        # base seconds for restart backoff
RESTART_BACKOFF_MAX = 300        # max seconds (5 min) between restart attempts

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ]
)
log = logging.getLogger("mstpistation-agent")


def discover_services(config, hardware) -> list:
    """Systemd services to watch on THIS device, derived from the deployed
    profile's module set.

    Self-healing therefore covers exactly what the device actually runs — the
    same agent logic adapts per device with zero per-model configuration.
    Container modules are excluded (Docker manages their lifecycle), as are the
    agent's own units (it must never try to restart itself).
    """
    from core.modules import ModuleManager
    from core.profiles import ProfileManager

    services: list = []
    seen = set()

    def _add(svc: str):
        svc = str(svc or "").strip()
        if svc and svc not in seen and svc not in ("mstpistation-agent", "mstpistation-watchdog"):
            seen.add(svc)
            services.append(svc)

    try:
        mm = ModuleManager(MSTPISTATION_DIR, config, hardware)
        pm = ProfileManager(MSTPISTATION_DIR, config, hardware)
        profile_name = config.get("node.profile")
        profile = pm.load(profile_name) if profile_name else None
        module_names = list((profile or {}).get("modules", []))
        if not module_names:
            module_names = [m["name"] for m in mm.list_modules()]
        for name in module_names:
            meta = mm._load_meta(name)
            if meta.get("type", "native") in ("docker", "container"):
                continue
            svc = meta.get("service")
            _add(svc if svc is not None else f"mstpistation-{name}")
    except Exception as e:
        log.debug(f"service discovery failed: {e}")

    if not services:   # safe fallback if discovery yields nothing
        for svc in ("reticulum", "mstpistation-hostapd", "batman-adv", "dnsmasq"):
            _add(svc)
    return services


class ServiceWatchdog:
    """Watches systemd services and restarts them on failure."""

    def __init__(self, services: list):
        self.services = services
        self.restart_counts: Dict[str, int] = {}
        self.last_restart: Dict[str, float] = {}
        self.failure_counts: Dict[str, int] = {}

    def check_and_heal(self):
        for svc in self.services:
            state = self._service_state(svc)
            if state == "failed":
                self._handle_failure(svc)
            elif state == "active":
                # Reset backoff on recovery
                if svc in self.failure_counts and self.failure_counts[svc] > 0:
                    log.info(f"{svc} recovered")
                    self.failure_counts[svc] = 0

    def _service_state(self, service: str) -> str:
        try:
            r = subprocess.run(
                ["systemctl", "is-active", service],
                capture_output=True, text=True, timeout=5
            )
            return r.stdout.strip()
        except Exception:
            return "unknown"

    def _handle_failure(self, service: str):
        count = self.failure_counts.get(service, 0)
        last = self.last_restart.get(service, 0)
        backoff = min(RESTART_BACKOFF_BASE * (2 ** count), RESTART_BACKOFF_MAX)

        if time.time() - last < backoff:
            return

        log.warning(f"Service {service} failed (attempt #{count+1}), restarting (backoff={backoff}s)")
        try:
            subprocess.run(["systemctl", "restart", service], timeout=30, check=False)
            self.failure_counts[service] = count + 1
            self.last_restart[service] = time.time()
        except Exception as e:
            log.error(f"Failed to restart {service}: {e}")


class NetworkFailover:
    """Monitors uplink interfaces and triggers failover."""

    PRIORITY_ORDER = ["eth0", "usb0", "wwan0", "ppp0"]

    def __init__(self, config: Config):
        self.config = config
        self.current_uplink: str = ""
        self.probe_target = "8.8.8.8"

    def check_and_failover(self):
        uplink = self.config.get("network.uplink_interface", "eth0")
        if not self._probe(uplink):
            log.warning(f"Uplink {uplink} unreachable, scanning for alternatives")
            for iface in self.PRIORITY_ORDER:
                if iface == uplink:
                    continue
                if self._iface_up(iface) and self._probe_via(iface):
                    log.info(f"Failing over to {iface}")
                    self._set_default_route(iface)
                    self.config.set("network.uplink_interface", iface)
                    break

    def _probe(self, iface: str) -> bool:
        return self._probe_via(iface)

    def _probe_via(self, iface: str) -> bool:
        try:
            r = subprocess.run(
                ["ping", "-I", iface, "-c1", "-W3", self.probe_target],
                capture_output=True, timeout=5
            )
            return r.returncode == 0
        except Exception:
            return False

    def _iface_up(self, iface: str) -> bool:
        path = Path(f"/sys/class/net/{iface}/operstate")
        try:
            return path.read_text().strip() == "up"
        except Exception:
            return False

    def _gateway_for(self, iface: str) -> str:
        """Best-effort next-hop for an interface (empty for point-to-point links)."""
        try:
            r = subprocess.run(["ip", "-j", "route", "show", "dev", iface],
                               capture_output=True, text=True, timeout=5)
            for rt in json.loads(r.stdout or "[]"):
                if rt.get("gateway"):
                    return rt["gateway"]
        except Exception:
            pass
        return ""

    def _set_default_route(self, iface: str):
        # Use `ip route replace` (atomic) instead of del-all + add: this swaps
        # only the default route and never strips unrelated routes. Ethernet
        # needs a gateway; LTE/PPP links are point-to-point (no gateway).
        gw = self._gateway_for(iface)
        cmd = (["ip", "route", "replace", "default", "via", gw, "dev", iface]
               if gw else
               ["ip", "route", "replace", "default", "dev", iface])
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if r.returncode == 0:
                log.info(f"Default route set via {iface}" + (f" (gw {gw})" if gw else ""))
            else:
                log.error(f"Failed to set default route via {iface}: {r.stderr.strip()}")
        except Exception as e:
            log.error(f"Failed to set default route: {e}")


class PeerDiscovery:
    """Discovers Mst-PI-Station peers on the mesh via batman-adv and Reticulum."""

    def __init__(self):
        self.peers: list = []

    def scan(self):
        peers = []

        # batman-adv neighbors
        try:
            r = subprocess.run(
                ["batctl", "n", "-H"], capture_output=True, text=True, timeout=5
            )
            if r.returncode == 0:
                for line in r.stdout.strip().split("\n"):
                    parts = line.split()
                    if len(parts) >= 3:
                        peers.append({
                            "mac": parts[0],
                            "transport": "batman-adv",
                            "iface": parts[1],
                            "last_seen": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        })
        except Exception:
            pass

        # Reticulum announce log — parse announced destinations
        rns_log = Path("/var/log/mstpistation/reticulum.log")
        if rns_log.exists():
            try:
                lines = rns_log.read_text().split("\n")[-200:]
                for line in lines:
                    if "Received announce" in line or "Added" in line:
                        pass  # Parse RNS peer announcements here
            except Exception:
                pass

        self.peers = peers
        self._save()

    def _save(self):
        PEERS_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(PEERS_FILE, "w") as f:
            json.dump(self.peers, f, indent=2)


class StatusCollector:
    """Collects node health status and writes status.json."""

    def __init__(self, config: Config, hardware: Hardware, services=None):
        self.config = config
        self.hardware = hardware
        self.services = services or []

    def collect(self) -> Dict[str, Any]:
        status = {
            "node": self.config.get("node.name", "mstpistation-node"),
            "profile": self.config.get("node.profile", "unknown"),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "uptime_seconds": self._uptime(),
            "healthy": True,
            "system": self._system_stats(),
            "services": self._service_states(),
            "interfaces": self._interface_states(),
            "mesh": self._mesh_stats(),
        }
        failed = [s for s in status["services"].values() if s == "failed"]
        if failed:
            status["healthy"] = False
            status["failed_services"] = failed
        return status

    def write(self, status: Dict[str, Any]):
        STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(STATUS_FILE, "w") as f:
            json.dump(status, f, indent=2)

    def _uptime(self) -> int:
        try:
            with open("/proc/uptime") as f:
                return int(float(f.read().split()[0]))
        except Exception:
            return 0

    def _system_stats(self) -> Dict[str, Any]:
        stats = {}
        try:
            with open("/proc/loadavg") as f:
                parts = f.read().split()
                stats["load_1m"] = float(parts[0])
                stats["load_5m"] = float(parts[1])
        except Exception:
            pass

        try:
            with open("/proc/meminfo") as f:
                mem = {}
                for line in f:
                    k, v = line.split(":", 1)
                    mem[k.strip()] = int(v.split()[0])
            total = mem.get("MemTotal", 0)
            avail = mem.get("MemAvailable", 0)
            stats["mem_total_mb"] = total // 1024
            stats["mem_used_mb"] = (total - avail) // 1024
        except Exception:
            pass

        # CPU temperature (Pi-specific + generic hwmon)
        temp_paths = [
            "/sys/class/thermal/thermal_zone0/temp",
            "/sys/class/hwmon/hwmon0/temp1_input",
        ]
        for tp in temp_paths:
            try:
                raw = int(Path(tp).read_text().strip())
                stats["cpu_temp_c"] = raw / 1000
                break
            except Exception:
                pass

        return stats

    def _service_states(self) -> Dict[str, str]:
        services = self.services or [
            "reticulum", "mstpistation-hostapd", "batman-adv",
            "dnsmasq", "mstpistation-lxmf"
        ]
        states = {}
        for svc in services:
            try:
                r = subprocess.run(
                    ["systemctl", "is-active", svc],
                    capture_output=True, text=True, timeout=3
                )
                states[svc] = r.stdout.strip()
            except Exception:
                states[svc] = "unknown"
        return states

    def _interface_states(self) -> list:
        try:
            r = subprocess.run(
                ["ip", "-j", "addr", "show"],
                capture_output=True, text=True, timeout=5
            )
            ifaces = json.loads(r.stdout)
            result = []
            for iface in ifaces:
                name = iface.get("ifname", "")
                if name == "lo":
                    continue
                flags = iface.get("flags", [])
                state = "UP" if "UP" in flags else "DOWN"
                ips = []
                for a in iface.get("addr_info", []):
                    if a.get("family") == "inet":
                        ips.append(f"{a['local']}/{a['prefixlen']}")
                result.append({"name": name, "state": state, "addresses": ips})
            return result
        except Exception:
            return []

    def _mesh_stats(self) -> Dict[str, Any]:
        stats = {"batman_peers": 0, "batman_gw": None}
        try:
            r = subprocess.run(
                ["batctl", "n", "-H"],
                capture_output=True, text=True, timeout=5
            )
            if r.returncode == 0:
                peers = [l for l in r.stdout.strip().split("\n") if l.strip()]
                stats["batman_peers"] = len(peers)
        except Exception:
            pass
        return stats


class MstPiStationAgent:
    """Main agent process."""

    def __init__(self, watchdog_only: bool = False):
        self.running = True
        self.watchdog_only = watchdog_only
        self.config = Config()
        self.hardware = Hardware()
        # Services to watch are derived from the deployed profile, so the same
        # agent self-heals whatever THIS device runs (no per-model config).
        self.services = discover_services(self.config, self.hardware)
        self.watchdog = ServiceWatchdog(self.services)
        self.failover = NetworkFailover(self.config)
        self.peer_discovery = PeerDiscovery()
        self.status_collector = StatusCollector(self.config, self.hardware, self.services)
        self._setup_signal_handlers()
        log.info(f"Watching {len(self.services)} service(s): {', '.join(self.services) or 'none'}")

    def _setup_signal_handlers(self):
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGHUP, self._handle_reload)

    def _handle_signal(self, signum, frame):
        log.info(f"Received signal {signum}, shutting down")
        self.running = False

    def _handle_reload(self, signum, frame):
        log.info("SIGHUP received, reloading config")
        self.config = Config()
        self.hardware.reload()
        # Re-derive the watch list in case the profile changed; keep the existing
        # watchdog/collector objects so backoff state survives the reload.
        self.services = discover_services(self.config, self.hardware)
        self.watchdog.services = self.services
        self.status_collector.config = self.config
        self.status_collector.services = self.services
        self.failover.config = self.config
        log.info(f"Reloaded — watching {len(self.services)} service(s)")

    def run(self):
        mode = "watchdog-only" if self.watchdog_only else "full"
        log.info(f"Mst-PI-Station agent starting ({mode}) — node: {self.config.get('node.name')}")
        self._write_pid()

        # Initial status write (full mode only)
        if not self.watchdog_only:
            status = self.status_collector.collect()
            self.status_collector.write(status)

        last_health = 0.0
        last_failover = 0.0
        last_peers = 0.0

        while self.running:
            now = time.time()

            if now - last_health >= HEALTH_CHECK_INTERVAL:
                if self.watchdog_only:
                    # Secondary healer: restart failed units only, nothing else.
                    try:
                        self.watchdog.check_and_heal()
                    except Exception as e:
                        log.error(f"Watchdog error: {e}")
                else:
                    self._run_health_check()
                last_health = now

            if not self.watchdog_only:
                if now - last_failover >= FAILOVER_CHECK_INTERVAL:
                    try:
                        self.failover.check_and_failover()
                    except Exception as e:
                        log.error(f"Failover check error: {e}")
                    last_failover = now

                if now - last_peers >= PEER_DISCOVERY_INTERVAL:
                    try:
                        self.peer_discovery.scan()
                    except Exception as e:
                        log.debug(f"Peer scan error: {e}")
                    last_peers = now

            time.sleep(5)

        self._cleanup()

    def _run_health_check(self):
        try:
            self.watchdog.check_and_heal()
            status = self.status_collector.collect()
            self.status_collector.write(status)
            if not status["healthy"]:
                log.warning(f"Node unhealthy: {status.get('failed_services', [])}")
        except Exception as e:
            log.error(f"Health check error: {e}")

    def _write_pid(self):
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(os.getpid()))

    def _cleanup(self):
        log.info("Agent stopping")
        try:
            PID_FILE.unlink(missing_ok=True)
        except Exception:
            pass


def main():
    import argparse
    parser = argparse.ArgumentParser(prog="mstpistation-agent",
                                     description="Mst-PI-Station node agent / watchdog")
    parser.add_argument("--watchdog-only", action="store_true",
                        help="Run only the service self-healer (no status/failover/peer scan)")
    parser.add_argument("--once", action="store_true",
                        help="Run a single pass and exit (useful for cron/testing)")
    args = parser.parse_args()

    # Ensure runtime dirs exist
    for d in [STATUS_FILE.parent, LOG_FILE.parent, PEERS_FILE.parent]:
        d.mkdir(parents=True, exist_ok=True)

    agent = MstPiStationAgent(watchdog_only=args.watchdog_only)
    if args.once:
        if args.watchdog_only:
            agent.watchdog.check_and_heal()
        else:
            agent._run_health_check()
        return
    agent.run()


if __name__ == "__main__":
    main()
