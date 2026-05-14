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
            "capabilities": {"wifi_ap": 0, "wifi_mesh": 0, "has_rnode": False, "has_lte": False}
        }
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal"):
                        data["ram_mb"] = int(line.split()[1]) // 1024
                        break
        except Exception:
            pass

        # Basic interface detection
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

    def best_ap_interface(self) -> Optional[str]:
        """Return best interface for AP mode."""
        wifi = self.wifi_interfaces
        if not wifi:
            return None
        # Prefer built-in (wlan0 on Pi) for AP — it has better driver support
        for iface in wifi:
            if iface == "wlan0":
                return iface
        return wifi[0]

    def best_mesh_interface(self) -> Optional[str]:
        """Return best interface for mesh (batman-adv). Prefer second Wi-Fi adapter."""
        wifi = self.wifi_interfaces
        if not wifi:
            return None
        if len(wifi) >= 2:
            # Use wlan1 (USB adapter) for mesh — better ibss/mesh_point support
            return wifi[1]
        # Single radio: share for both, but warn
        return wifi[0]

    def best_uplink_interface(self) -> Optional[str]:
        """Return best uplink interface (ethernet > LTE > None)."""
        if self.ethernet_interfaces:
            return self.ethernet_interfaces[0]
        wwan = self._data.get("interfaces", {}).get("wwan", [])
        if wwan:
            return wwan[0]
        if self.lte_devices:
            return "usb0"
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

    def profile_warnings(self, profile: str) -> List[str]:
        """Return warnings for a profile given current hardware."""
        warnings = []
        if profile in ("hotspot", "field-node", "mesh-hub", "relay"):
            if not self.has_wifi:
                warnings.append("No Wi-Fi interfaces detected. Hotspot/mesh requires Wi-Fi.")
            elif not self.has_dual_wifi:
                warnings.append(
                    "Only one Wi-Fi interface detected. "
                    "Using single radio for both AP and mesh will reduce performance."
                )
        if profile in ("relay", "field-node") and not self.has_rnode:
            warnings.append("No RNode detected. LoRa transport will not be available.")
        if profile == "lte-gateway" and not self.has_lte:
            warnings.append("No LTE modem detected. Install a supported USB LTE modem.")
        return warnings

    def reload(self):
        """Reload hardware info from disk."""
        self._load()

    def to_dict(self) -> Dict[str, Any]:
        return self._data
