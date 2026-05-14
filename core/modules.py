"""Module management for Aetherium."""

import os
import subprocess
import yaml
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from core.config import Config
from core.hardware import Hardware


INSTALL_DIR = Path(__file__).parent.parent
MODULES_DIR = INSTALL_DIR / "modules"


class ModuleManager:
    def __init__(self, install_dir: Path, config: Config, hardware: Hardware):
        self.install_dir = install_dir
        self.modules_dir = install_dir / "modules"
        self.config = config
        self.hardware = hardware

    def list_modules(self) -> List[Dict[str, Any]]:
        """List all modules with their metadata and current status."""
        result = []
        for module_dir in sorted(self.modules_dir.iterdir()):
            if not module_dir.is_dir():
                continue
            meta_file = module_dir / "module.yaml"
            if not meta_file.exists():
                continue
            with open(meta_file) as f:
                meta = yaml.safe_load(f) or {}
            meta["name"] = module_dir.name
            meta["status"] = self._get_status(module_dir.name, meta)
            result.append(meta)
        return result

    def _get_status(self, name: str, meta: Dict) -> str:
        """Determine current module status."""
        mod_type = meta.get("type", "native")

        if mod_type == "native":
            service = meta.get("service", f"aetherium-{name}")
            return self.get_service_status(service)
        elif mod_type == "container":
            return self._get_container_status(name)
        elif mod_type == "both":
            native_svc = meta.get("service", f"aetherium-{name}")
            native_st = self.get_service_status(native_svc)
            if native_st == "active":
                return "active"
            return self._get_container_status(name)

        # Check if binary/package exists
        binary = meta.get("binary")
        if binary and _which(binary):
            return "installed"
        return "available"

    def get_service_status(self, service_name: str) -> str:
        """Get systemd service status."""
        try:
            result = subprocess.run(
                ["systemctl", "is-active", service_name],
                capture_output=True, text=True, timeout=5
            )
            return result.stdout.strip()
        except Exception:
            return "unknown"

    def _get_container_status(self, name: str) -> str:
        """Get Docker container status."""
        try:
            result = subprocess.run(
                ["docker", "compose", "-f",
                 str(self.modules_dir / name / "docker-compose.yml"),
                 "ps", "--format", "json"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0 and result.stdout.strip():
                return "active"
            return "inactive"
        except Exception:
            return "unavailable"

    def deploy_module(self, name: str, profile: Dict) -> Tuple[bool, str]:
        """Install and configure a module as part of a profile deploy."""
        module_dir = self.modules_dir / name
        if not module_dir.exists():
            return False, f"Module '{name}' not found"

        meta_file = module_dir / "module.yaml"
        meta = {}
        if meta_file.exists():
            with open(meta_file) as f:
                meta = yaml.safe_load(f) or {}

        # Check hardware requirements
        hw_req = meta.get("requires_hardware", [])
        for req in hw_req:
            if req == "wifi" and not self.hardware.has_wifi:
                return False, "requires Wi-Fi (not detected)"
            if req == "rnode" and not self.hardware.has_rnode:
                return True, "skipped (RNode not detected)"
            if req == "lte" and not self.hardware.has_lte:
                return True, "skipped (LTE modem not detected)"

        # Run install.sh
        install_script = module_dir / "install.sh"
        if install_script.exists():
            success, msg = self._run_script(install_script, name, profile)
            if not success:
                return False, f"install failed: {msg}"

        # Run configure.sh
        configure_script = module_dir / "configure.sh"
        if configure_script.exists():
            env = self._build_env(name, profile)
            success, msg = self._run_script(configure_script, name, profile, env=env)
            if not success:
                return False, f"configure failed: {msg}"

        return True, "ok"

    def enable(self, name: str) -> Tuple[bool, str]:
        """Enable a module outside of a full profile deploy."""
        module_dir = self.modules_dir / name
        if not module_dir.exists():
            return False, f"Module '{name}' not found"

        # Run install + configure with current profile context
        current_profile_name = self.config.get("node.profile", "relay")
        from core.profiles import ProfileManager
        pm = ProfileManager(self.install_dir, self.config, self.hardware)
        profile = pm.load(current_profile_name) or {}
        return self.deploy_module(name, profile)

    def disable(self, name: str) -> Tuple[bool, str]:
        """Disable and stop a module."""
        module_dir = self.modules_dir / name
        if not module_dir.exists():
            return False, f"Module '{name}' not found"

        meta_file = module_dir / "module.yaml"
        meta = {}
        if meta_file.exists():
            with open(meta_file) as f:
                meta = yaml.safe_load(f) or {}

        mod_type = meta.get("type", "native")

        if mod_type in ("native", "both"):
            service = meta.get("service", f"aetherium-{name}")
            try:
                subprocess.run(["systemctl", "stop", service], check=False, timeout=15)
                subprocess.run(["systemctl", "disable", service], check=False, timeout=10)
                return True, "stopped"
            except Exception as e:
                return False, str(e)

        elif mod_type == "container":
            try:
                subprocess.run(
                    ["docker", "compose", "-f",
                     str(module_dir / "docker-compose.yml"), "down"],
                    check=False, timeout=30
                )
                return True, "stopped"
            except Exception as e:
                return False, str(e)

        return True, "disabled"

    def update(self, name: str) -> Tuple[bool, str]:
        """Update a module."""
        module_dir = self.modules_dir / name
        update_script = module_dir / "update.sh"
        if update_script.exists():
            success, msg = self._run_script(update_script, name, {})
            return success, msg
        return False, "no update script"

    def _run_script(self, script: Path, module_name: str,
                    profile: Dict, env: Optional[Dict] = None) -> Tuple[bool, str]:
        """Run a module script with proper environment."""
        run_env = os.environ.copy()
        run_env.update({
            "AETHERIUM_DIR": str(self.install_dir),
            "AETHERIUM_CONFIG_DIR": "/etc/aetherium",
            "AETHERIUM_DATA_DIR": "/var/lib/aetherium",
            "AETHERIUM_LOG_DIR": "/var/log/aetherium",
            "MODULE_NAME": module_name,
            "MODULE_DIR": str(self.modules_dir / module_name),
            "TEMPLATES_DIR": str(self.install_dir / "templates"),
        })
        if env:
            run_env.update(env)

        try:
            result = subprocess.run(
                ["bash", str(script)],
                env=run_env,
                capture_output=True, text=True,
                timeout=300
            )
            if result.returncode == 0:
                return True, result.stdout.strip()
            else:
                return False, result.stderr.strip() or result.stdout.strip()
        except subprocess.TimeoutExpired:
            return False, "script timed out after 5 minutes"
        except Exception as e:
            return False, str(e)

    def _build_env(self, module_name: str, profile: Dict) -> Dict[str, str]:
        """Build environment variables for module scripts from profile context."""
        env = {}
        net = profile.get("network", {})
        env["AP_INTERFACE"] = net.get("ap_interface", "wlan0")
        env["MESH_INTERFACE"] = net.get("mesh_interface", "wlan0")
        env["UPLINK_INTERFACE"] = net.get("uplink_interface", "eth0")
        env["HOTSPOT_SUBNET"] = net.get("hotspot_subnet", "192.168.42.0/24")
        env["HOTSPOT_IP"] = net.get("hotspot_ip", "192.168.42.1")

        hs = profile.get("hotspot", {})
        env["HOTSPOT_SSID"] = hs.get("ssid", "Aetherium")
        env["HOTSPOT_CHANNEL"] = str(hs.get("channel", 6))
        env["HOTSPOT_BAND"] = hs.get("band", "2.4GHz")
        env["HOTSPOT_PASSWORD"] = hs.get("password", "")
        env["HOTSPOT_HIDDEN"] = "1" if hs.get("hidden") else "0"

        node = profile.get("node", {})
        env["NODE_NAME"] = node.get("name", "aetherium-node")
        env["NODE_PROFILE"] = node.get("profile", "relay")

        rns = profile.get("reticulum", {})
        env["RNS_ENABLED"] = "1" if rns.get("enabled") else "0"
        env["RNS_CONFIG_DIR"] = rns.get("config_dir", "/etc/reticulum")

        bat = profile.get("batman_adv", {})
        env["BATMAN_ENABLED"] = "1" if bat.get("enabled") else "0"
        env["BATMAN_INTERFACE"] = bat.get("interface", "wlan0")
        env["BATMAN_GW_MODE"] = bat.get("gw_mode", "off")

        rnode = profile.get("rnode", {})
        env["RNODE_PORT"] = rnode.get("port", "")
        env["RNODE_FREQ"] = str(rnode.get("frequency", 915000000))
        env["RNODE_BW"] = str(rnode.get("bandwidth", 125000))
        env["RNODE_SF"] = str(rnode.get("sf", 7))
        env["RNODE_TX_POWER"] = str(rnode.get("tx_power", 17))

        return env


def _which(binary: str) -> bool:
    import shutil
    return shutil.which(binary) is not None
