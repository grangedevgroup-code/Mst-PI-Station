"""Configuration management for Aetherium."""

import os
import yaml
from pathlib import Path
from typing import Any, Dict, List, Optional


CONFIG_DIR = Path("/etc/aetherium")
CONFIG_FILE = CONFIG_DIR / "aetherium.yaml"
HARDWARE_FILE = CONFIG_DIR / "hardware.yaml"
INSTALL_DIR = Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULTS_DIR = INSTALL_DIR / "config" / "defaults"
HARDWARE_DEFAULTS_DIR = INSTALL_DIR / "config" / "hardware"


class Config:
    def __init__(self, config_file: Optional[Path] = None):
        self.config_file = config_file or CONFIG_FILE
        self.data: Dict[str, Any] = {}
        self._load()

    def _load(self):
        # Load site config
        if self.config_file.exists():
            with open(self.config_file) as f:
                self.data = yaml.safe_load(f) or {}
        else:
            self.data = self._defaults()

    def _defaults(self) -> Dict[str, Any]:
        return {
            "node": {
                "name": os.uname().nodename,
                "profile": None,
                "location": "",
            },
            "network": {
                "ap_interface": "auto",
                "mesh_interface": "auto",
                "uplink_interface": "auto",
                "hotspot_subnet": "192.168.42.0/24",
                "hotspot_ip": "192.168.42.1",
            },
            "hotspot": {
                "enabled": False,
                "ssid": f"Aetherium-{os.uname().nodename}",
                "channel": 6,
                "band": "2.4GHz",
                "password": "",
                "captive_portal": True,
                "hidden": False,
            },
            "reticulum": {
                "enabled": False,
                "config_dir": "/etc/reticulum",
                "interfaces": [],
            },
            "batman_adv": {
                "enabled": False,
                "interface": "auto",
                "gw_mode": "off",
            },
            "modules": {},
        }

    def get(self, key: str, default: Any = None) -> Any:
        """Get a value using dot notation: node.name"""
        parts = key.split(".")
        val = self.data
        for part in parts:
            if not isinstance(val, dict):
                return default
            val = val.get(part, None)
            if val is None:
                return default
        return val

    def set(self, key: str, value: Any):
        """Set a value using dot notation."""
        parts = key.split(".")
        d = self.data
        for part in parts[:-1]:
            if part not in d or not isinstance(d[part], dict):
                d[part] = {}
            d = d[part]
        # Type coercion
        if isinstance(value, str):
            if value.lower() == "true":
                value = True
            elif value.lower() == "false":
                value = False
            elif value.isdigit():
                value = int(value)
        d[parts[-1]] = value

    def save(self):
        """Write config to disk."""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(self.config_file, "w") as f:
            yaml.dump(self.data, f, default_flow_style=False, allow_unicode=True)

    def validate(self) -> List[str]:
        """Return list of validation errors."""
        errors = []
        if not self.get("node.name"):
            errors.append("node.name is required")
        profile = self.get("node.profile")
        valid_profiles = ["relay", "field-node", "hotspot", "mesh-hub",
                          "lte-gateway", "emergency", "solar-relay", "local-services"]
        if profile and profile not in valid_profiles:
            errors.append(f"node.profile '{profile}' is not valid")
        return errors

    def get_module_config(self, module_name: str) -> Dict[str, Any]:
        """Get per-module config section."""
        return self.get(f"modules.{module_name}") or {}

    def module_enabled(self, module_name: str) -> bool:
        """Check if a module is explicitly enabled in config."""
        return bool(self.get(f"modules.{module_name}.enabled", False))

    def load_hardware_defaults(self) -> Dict[str, Any]:
        """Load hardware-specific config overrides."""
        hw_file = HARDWARE_FILE
        if not hw_file.exists():
            return {}
        with open(hw_file) as f:
            hw = yaml.safe_load(f) or {}

        model = hw.get("model", "generic")
        hw_defaults_file = HARDWARE_DEFAULTS_DIR / f"{model}.yaml"
        if not hw_defaults_file.exists():
            hw_defaults_file = HARDWARE_DEFAULTS_DIR / "generic.yaml"

        if hw_defaults_file.exists():
            with open(hw_defaults_file) as f:
                return yaml.safe_load(f) or {}
        return {}

    def merged(self) -> Dict[str, Any]:
        """Return config merged with hardware defaults and module defaults."""
        import copy
        result = copy.deepcopy(self._defaults())
        hw_defaults = self.load_hardware_defaults()
        _deep_merge(result, hw_defaults)
        _deep_merge(result, self.data)
        return result


def _deep_merge(base: dict, override: dict) -> dict:
    for key, val in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(val, dict):
            _deep_merge(base[key], val)
        else:
            base[key] = val
    return base
