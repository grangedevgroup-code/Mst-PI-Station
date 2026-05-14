"""Profile loading and resolution for Aetherium."""

import yaml
from pathlib import Path
from typing import Any, Dict, List, Optional

from core.config import Config, _deep_merge
from core.hardware import Hardware


INSTALL_DIR = Path(__file__).parent.parent
PROFILES_DIR = INSTALL_DIR / "profiles"


class ProfileManager:
    def __init__(self, install_dir: Path, config: Config, hardware: Hardware):
        self.install_dir = install_dir
        self.profiles_dir = install_dir / "profiles"
        self.config = config
        self.hardware = hardware

    def load(self, name: str) -> Optional[Dict[str, Any]]:
        """Load and resolve a profile, merging hardware capabilities."""
        profile_file = self.profiles_dir / f"{name}.yaml"
        if not profile_file.exists():
            return None

        with open(profile_file) as f:
            profile = yaml.safe_load(f) or {}

        # Auto-fill interface assignments from hardware
        suggested = self.hardware.suggested_interfaces()
        net = profile.setdefault("network", {})

        if net.get("ap_interface") == "auto" or not net.get("ap_interface"):
            net["ap_interface"] = suggested["ap"] or "wlan0"
        if net.get("mesh_interface") == "auto" or not net.get("mesh_interface"):
            net["mesh_interface"] = suggested["mesh"] or "wlan0"
        if net.get("uplink_interface") == "auto" or not net.get("uplink_interface"):
            net["uplink_interface"] = suggested["uplink"] or "eth0"

        # Override with site config
        site_cfg = self.config.merged()
        _deep_merge(profile, {
            k: v for k, v in site_cfg.items()
            if k in ("node", "network", "hotspot", "reticulum", "batman_adv")
        })

        # Inject hardware-detected devices
        if suggested["first_rnode"]:
            rn = profile.setdefault("rnode", {})
            if not rn.get("port"):
                rn["port"] = suggested["first_rnode"]

        return profile

    def list_profiles(self) -> List[Dict[str, str]]:
        """List all available profiles."""
        result = []
        for f in sorted(self.profiles_dir.glob("*.yaml")):
            name = f.stem
            with open(f) as fh:
                data = yaml.safe_load(fh) or {}
            result.append({
                "name": name,
                "description": data.get("description", ""),
                "modules": data.get("modules", []),
            })
        return result
