"""Hardware abstraction layer for Aetherium."""

import os
import subprocess
import yaml
from pathlib import Path
from typing import List, Optional, Dict, Any


HARDWARE_FILE = Path("/etc/aetherium/hardware.yaml")


class Hardware:
    def __init__(self):
        self._data: Dict[str, Any] = {}
        self._load()

    def _load(self):
        if HARDWARE_FILE.exists():
            with open(HARDWARE_FILE) as f:
                self._data = yaml.safe_load(f) or {}
        else:
            self._data = self._detect_basic()

    def _detect_basic(self) -> Dict[str, Any]:
        import platform
        data = {
            "model": "generic",
            "arch": platform.machine(),
            "is_pi": False,
            "cpu_cores": os.cpu_count() or 1,
            "ram_mb": 0,
            "interfaces": {"wifi": [], "ethernet": [], "wwan": []},
            "devices": {"rnode": [], "lte_modem": []},
            "capabilities": {
                "wifi_ap": 0, "wifi_mesh": 0,
                "has_rnode": False, "has_lte": False,
                "ap_capable_interfaces": [],
                "mesh_capable_interfaces": [],
            },
        }
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal"):
                        data["ram_mb"] = int(line.split()[1]) // 1024
                        break
        except Exception:
            pass

        try:
            for entry in Path("/sys/class/net").iterdir():
                name = entry.name
                if (entry / "wireless").exists():
                    data["interfaces"]["wifi"].append(name)
                elif name.startswith(("eth", "en", "eno", "enp")):
                    data["interfaces"]["ethernet"].append(name)
        except Exception:
            pass

        return data

    # ── Properties ──────────────────────────────────────────────────────────

    @property
    def model(self) -> str:
        return self._data.get("model", "generic")

    @property
    def arch(self) -> str:
        return self._data.get("arch", os.uname().machine)

    @property
    def is_pi(self) -> bool:
        return bool(self._data.get("is_pi", False))

    @property
    def cpu_cores(self) -> int:
        return self._data.get("cpu_cores", 1)

    @property
    def ram_mb(self) -> int:
        return self._data.get("ram_mb", 0)

    @property
    def wifi_interfaces(self) -> List[str]:
        return self._data.get("interfaces", {}).get("wifi", [])

    @property
    def ethernet_interfaces(self) -> List[str]:
        return self._data.get("interfaces", {}).get("ethernet", [])

    @property
    def rnode_devices(self) -> List[str]:
        return self._data.get("devices", {}).get("rnode", [])

    @property
    def lte_devices(self) -> List[str]:
        return self._data.get("devices", {}).get("lte_modem", [])

    @property
    def has_rnode(self) -> bool:
        return bool(self.rnode_devices)

    @property
    def has_lte(self) -> bool:
        return bool(self.lte_devices)

    @property
    def has_wifi(self) -> bool:
        return len(self.wifi_interfaces) > 0

    @property
    def has_dual_wifi(self) -> bool:
        return len(self.wifi_interfaces) >= 2

    # ── Interface capability checks ──────────────────────────────────────────

    def ap_capable_interfaces(self) -> List[str]:
        """Return interfaces confirmed to support AP mode via iw."""
        # Check hardware.yaml if detect-hardware.sh already ran iw
        caps = self._data.get("capabilities", {})
        saved = caps.get("ap_capable_interfaces", [])
        if saved:
            return saved
        # Runtime fallback: probe with iw
        result = []
        for iface in self.wifi_interfaces:
            if self._iface_supports_ap(iface):
                result.append(iface)
        return result or self.wifi_interfaces  # assume all capable if iw unavailable

    def mesh_capable_interfaces(self) -> List[str]:
        """Return interfaces confirmed to support IBSS/mesh-point mode."""
        caps = self._data.get("capabilities", {})
        saved = caps.get("mesh_capable_interfaces", [])
        if saved:
            return saved
        result = []
        for iface in self.wifi_interfaces:
            if self._iface_supports_mesh(iface):
                result.append(iface)
        return result or self.wifi_interfaces

    @staticmethod
    def _iface_supports_ap(iface: str) -> bool:
        try:
            r = subprocess.run(
                ["iw", "dev", iface, "info"],
                capture_output=True, text=True, timeout=3
            )
            phy_line = next((l for l in r.stdout.splitlines() if "wiphy" in l), "")
            phy = "phy" + phy_line.split()[-1] if phy_line else ""
            if not phy:
                return False
            r2 = subprocess.run(
                ["iw", "phy", phy, "info"],
                capture_output=True, text=True, timeout=3
            )
            return bool(r2.returncode == 0 and
                        ("AP\n" in r2.stdout or "AP " in r2.stdout or "* AP\n" in r2.stdout))
        except Exception:
            return False

    @staticmethod
    def _iface_supports_mesh(iface: str) -> bool:
        try:
            r = subprocess.run(
                ["iw", "dev", iface, "info"],
                capture_output=True, text=True, timeout=3
            )
            phy_line = next((l for l in r.stdout.splitlines() if "wiphy" in l), "")
            phy = "phy" + phy_line.split()[-1] if phy_line else ""
            if not phy:
                return False
            r2 = subprocess.run(
                ["iw", "phy", phy, "info"],
                capture_output=True, text=True, timeout=3
            )
            return bool(r2.returncode == 0 and
                        ("IBSS" in r2.stdout or "mesh point" in r2.stdout))
        except Exception:
            return False

    @staticmethod
    def _iface_is_up(iface: str) -> bool:
        """Check if interface has carrier/is operationally up."""
        operstate = Path(f"/sys/class/net/{iface}/operstate")
        if operstate.exists():
            state = operstate.read_text().strip()
            return state in ("up", "unknown")
        # Fallback: check flags
        try:
            flags_path = Path(f"/sys/class/net/{iface}/flags")
            if flags_path.exists():
                flags = int(flags_path.read_text().strip(), 16)
                return bool(flags & 0x1)  # IFF_UP
        except Exception:
            pass
        return False

    # ── Regulatory domain ────────────────────────────────────────────────────

    def regulatory_domain(self) -> str:
        """Auto-detect ISO country code from hardware.yaml, iw, or timezone."""
        # Use previously detected value from hardware.yaml first
        saved = self._data.get("regulatory_domain", "")
        if saved and saved != "00":
            return saved.upper()
        return self._detect_regulatory_domain()

    @staticmethod
    def _detect_regulatory_domain() -> str:
        """Auto-detect ISO country code from timezone/locale for regulatory compliance."""
        # Check iw reg already set
        try:
            r = subprocess.run(["iw", "reg", "get"],
                               capture_output=True, text=True, timeout=3)
            for line in r.stdout.splitlines():
                if line.startswith("country") and len(line) > 8:
                    cc = line.split()[1].rstrip(":")
                    if len(cc) == 2 and cc.isalpha() and cc != "00":
                        return cc.upper()
        except Exception:
            pass

        # Derive from timezone
        tz = ""
        try:
            r = subprocess.run(["timedatectl", "show", "--property=Timezone", "--value"],
                               capture_output=True, text=True, timeout=3)
            tz = r.stdout.strip()
        except Exception:
            pass

        if not tz:
            try:
                tz_path = Path("/etc/timezone")
                if tz_path.exists():
                    tz = tz_path.read_text().strip()
                else:
                    localtime = Path("/etc/localtime")
                    if localtime.is_symlink():
                        target = str(localtime.resolve())
                        if "/zoneinfo/" in target:
                            tz = target.split("/zoneinfo/")[-1]
            except Exception:
                pass

        # Region → country code map (covers most common timezones)
        _TZ_CC = {
            "America/New_York": "US", "America/Chicago": "US",
            "America/Denver": "US", "America/Los_Angeles": "US",
            "America/Phoenix": "US", "America/Anchorage": "US",
            "America/Honolulu": "US", "America/Indiana": "US",
            "America/Toronto": "CA", "America/Vancouver": "CA",
            "America/Montreal": "CA", "America/Winnipeg": "CA",
            "America/Sao_Paulo": "BR", "America/Buenos_Aires": "AR",
            "America/Mexico_City": "MX",
            "Europe/London": "GB", "Europe/Dublin": "IE",
            "Europe/Paris": "FR", "Europe/Berlin": "DE",
            "Europe/Madrid": "ES", "Europe/Rome": "IT",
            "Europe/Amsterdam": "NL", "Europe/Brussels": "BE",
            "Europe/Warsaw": "PL", "Europe/Stockholm": "SE",
            "Europe/Oslo": "NO", "Europe/Copenhagen": "DK",
            "Europe/Helsinki": "FI", "Europe/Zurich": "CH",
            "Europe/Vienna": "AT", "Europe/Prague": "CZ",
            "Europe/Budapest": "HU", "Europe/Lisbon": "PT",
            "Europe/Athens": "GR", "Europe/Bucharest": "RO",
            "Europe/Kiev": "UA", "Europe/Moscow": "RU",
            "Asia/Tokyo": "JP", "Asia/Seoul": "KR",
            "Asia/Shanghai": "CN", "Asia/Hong_Kong": "HK",
            "Asia/Singapore": "SG", "Asia/Taipei": "TW",
            "Asia/Kolkata": "IN", "Asia/Karachi": "PK",
            "Asia/Bangkok": "TH", "Asia/Jakarta": "ID",
            "Asia/Manila": "PH", "Asia/Kuala_Lumpur": "MY",
            "Asia/Dubai": "AE", "Asia/Riyadh": "SA",
            "Asia/Jerusalem": "IL", "Asia/Beirut": "LB",
            "Australia/Sydney": "AU", "Australia/Melbourne": "AU",
            "Australia/Perth": "AU", "Australia/Brisbane": "AU",
            "Pacific/Auckland": "NZ",
            "Africa/Johannesburg": "ZA", "Africa/Lagos": "NG",
            "Africa/Cairo": "EG", "Africa/Nairobi": "KE",
        }
        if tz in _TZ_CC:
            return _TZ_CC[tz]
        # Match on region prefix
        if tz.startswith("America/"):
            return "US"
        if tz.startswith("Europe/"):
            return "DE"
        if tz.startswith("Australia/"):
            return "AU"
        return ""

    @staticmethod
    def lora_frequency_for_region(country_code: str) -> int:
        """Return appropriate LoRa frequency for region."""
        cc = country_code.upper()
        if cc in ("US", "CA", "MX", "BR", "AU", "NZ", "AR", "CL", "CO"):
            return 915000000   # 915 MHz
        if cc in ("JP",):
            return 920000000   # 920 MHz
        if cc in ("CN",):
            return 470000000   # 470 MHz
        # EU + most of Asia/Africa/ME → 868 MHz
        return 868000000

    # ── Profile suggestion ───────────────────────────────────────────────────

    def suggest_profile(self) -> str:
        """Suggest the most appropriate profile based on detected hardware."""
        has_rnode = self.has_rnode
        has_lte = self.has_lte
        wifi_count = len(self.wifi_interfaces)
        eth_count = len(self.ethernet_interfaces)
        low_ram = self.ram_mb > 0 and self.ram_mb < 512

        if has_lte and has_rnode:
            return "lte-gateway"  # full gateway with LoRa + LTE
        if has_lte:
            return "lte-gateway"
        if has_rnode and wifi_count >= 1:
            return "relay"        # LoRa relay with AP
        if has_rnode and wifi_count == 0:
            return "relay"        # headless LoRa relay
        if wifi_count >= 2 and eth_count >= 1:
            return "mesh-hub"     # dedicated hub with uplink
        if wifi_count >= 1 and eth_count >= 1:
            return "relay"        # single Wi-Fi + ethernet = relay
        if wifi_count >= 1 and low_ram:
            return "field-node"   # mobile, battery-constrained
        if wifi_count >= 1:
            return "relay"
        return "relay"            # safe default

    # ── Interface selectors ──────────────────────────────────────────────────

    def best_ap_interface(self) -> Optional[str]:
        """Return best interface for AP mode — prefers confirmed AP-capable, then wlan0."""
        capable = self.ap_capable_interfaces()
        if not capable:
            return None
        # Prefer wlan0 (Pi built-in) for AP — best driver stability
        if "wlan0" in capable:
            return "wlan0"
        return capable[0]

    def best_mesh_interface(self) -> Optional[str]:
        """Return best interface for mesh. Prefer second adapter (USB); fall back to wlan0."""
        capable = self.mesh_capable_interfaces()
        wifi = self.wifi_interfaces
        if not wifi:
            return None
        if len(wifi) >= 2:
            # Prefer non-wlan0 for mesh so wlan0 is free for AP
            for iface in capable:
                if iface != "wlan0":
                    return iface
            return wifi[1]
        return wifi[0]

    def best_uplink_interface(self) -> Optional[str]:
        """Return best uplink — prefer ethernet that's up, then WWAN, then None."""
        for iface in self.ethernet_interfaces:
            if self._iface_is_up(iface):
                return iface
        # Even if not up yet, return first ethernet (may come up later)
        if self.ethernet_interfaces:
            return self.ethernet_interfaces[0]
        wwan = self._data.get("interfaces", {}).get("wwan", [])
        if wwan:
            return wwan[0]
        if self.lte_devices:
            return "usb0"  # MM will create this
        return None

    def suggested_interfaces(self) -> Dict[str, Optional[str]]:
        """Return suggested interface assignments for a profile."""
        return {
            "ap": self.best_ap_interface(),
            "mesh": self.best_mesh_interface(),
            "uplink": self.best_uplink_interface(),
            "first_rnode": self.rnode_devices[0] if self.rnode_devices else None,
            "first_lte": self.lte_devices[0] if self.lte_devices else None,
        }

    # ── Warnings ─────────────────────────────────────────────────────────────

    def profile_warnings(self, profile: str) -> List[str]:
        """Return warnings for a profile given current hardware."""
        warnings = []
        if profile in ("hotspot", "field-node", "mesh-hub", "relay"):
            if not self.has_wifi:
                warnings.append("No Wi-Fi interfaces detected — hotspot/mesh requires Wi-Fi.")
            elif not self.has_dual_wifi:
                warnings.append(
                    "Single Wi-Fi adapter: AP and mesh will share one radio. "
                    "Add a USB Wi-Fi adapter for better performance."
                )
            if self.has_wifi and not self.ap_capable_interfaces():
                warnings.append(
                    f"Wi-Fi adapter may not support AP mode. "
                    "Verify with: iw phy phy0 info | grep AP"
                )
        if profile in ("relay", "field-node") and not self.has_rnode:
            warnings.append("No RNode detected — LoRa transport unavailable. "
                            "Connect an RNode and run: aetherium module enable rnode")
        if profile == "lte-gateway" and not self.has_lte:
            warnings.append("No LTE modem detected — install a supported USB LTE modem.")
        if self.ram_mb > 0 and self.ram_mb < 512 and profile in ("mesh-hub", "monitoring"):
            warnings.append(
                f"Low RAM ({self.ram_mb}MB) — heavy services (Matrix, Grafana) may cause OOM. "
                "Consider field-node or relay profile."
            )
        return warnings

    def reload(self):
        """Reload hardware info from disk."""
        self._load()

    def to_dict(self) -> Dict[str, Any]:
        return self._data
