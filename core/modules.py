"""Module management for Aetherium."""

import os
import subprocess
import yaml
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

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
        self._deploy_in_progress: Set[str] = set()   # cycle guard

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
        elif mod_type in ("docker", "container"):
            return self._get_container_status(name)
        elif mod_type == "both":
            native_svc = meta.get("service", f"aetherium-{name}")
            if self.get_service_status(native_svc) == "active":
                return "active"
            return self._get_container_status(name)
        binary = meta.get("binary")
        if binary and _which(binary):
            return "installed"
        return "available"

    def get_service_status(self, service_name: str) -> str:
        try:
            result = subprocess.run(
                ["systemctl", "is-active", service_name],
                capture_output=True, text=True, timeout=5
            )
            return result.stdout.strip()
        except Exception:
            return "unknown"

    def _get_container_status(self, name: str) -> str:
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

    def _load_meta(self, name: str) -> Dict:
        meta_file = self.modules_dir / name / "module.yaml"
        if not meta_file.exists():
            return {}
        with open(meta_file) as f:
            return yaml.safe_load(f) or {}

    def _resolve_deps(self, name: str, profile: Dict,
                      visited: Optional[Set[str]] = None) -> List[str]:
        """Return ordered list of dependencies that need deploying before `name`."""
        if visited is None:
            visited = set()
        if name in visited:
            return []   # cycle guard
        visited.add(name)

        meta = self._load_meta(name)
        deps = meta.get("depends", [])
        order = []
        for dep in deps:
            # Check if dep is already active
            dep_meta = self._load_meta(dep)
            dep_status = self._get_status(dep, dep_meta)
            if dep_status in ("active", "installed"):
                continue
            # Recurse for transitive deps
            order.extend(self._resolve_deps(dep, profile, visited))
            if dep not in order:
                order.append(dep)
        return order

    def deploy_module(self, name: str, profile: Dict,
                      _dep_chain: Optional[Set[str]] = None) -> Tuple[bool, str]:
        """Install and configure a module as part of a profile deploy."""
        module_dir = self.modules_dir / name
        if not module_dir.exists():
            return False, f"Module '{name}' not found"

        # Cycle detection
        if _dep_chain is None:
            _dep_chain = set()
        if name in _dep_chain:
            return False, f"Dependency cycle detected for '{name}'"
        _dep_chain = _dep_chain | {name}

        meta = self._load_meta(name)

        # ── Hardware requirements ────────────────────────────────────────────
        hw_req = meta.get("requires_hardware", [])
        for req in hw_req:
            if req == "wifi" and not self.hardware.has_wifi:
                return False, "requires Wi-Fi (not detected)"
            if req in ("rnode", "rtl_sdr") and not self.hardware.has_rnode:
                return True, f"skipped ({req} not detected)"
            if req in ("lte_modem", "lte") and not self.hardware.has_lte:
                return True, "skipped (LTE modem not detected)"

        # ── Dependency enforcement ───────────────────────────────────────────
        deps = meta.get("depends", [])
        for dep in deps:
            dep_meta = self._load_meta(dep)
            if not dep_meta:
                continue
            dep_status = self._get_status(dep, dep_meta)
            if dep_status not in ("active", "installed"):
                print(f"  [modules] Auto-deploying dependency: {dep} (required by {name})")
                ok, msg = self.deploy_module(dep, profile, _dep_chain)
                if not ok:
                    return False, f"dependency '{dep}' failed: {msg}"

        # ── Install ──────────────────────────────────────────────────────────
        install_script = module_dir / "install.sh"
        if install_script.exists():
            success, msg = self._run_script(install_script, name, profile)
            if not success:
                return False, f"install failed: {msg}"

        # ── Configure ────────────────────────────────────────────────────────
        configure_script = module_dir / "configure.sh"
        if configure_script.exists():
            env = self._build_env(name, profile)
            success, msg = self._run_script(configure_script, name, profile, env=env)
            if not success:
                return False, f"configure failed: {msg}"

        return True, "ok"

    def enable(self, name: str) -> Tuple[bool, str]:
        current_profile_name = self.config.get("node.profile", "relay")
        from core.profiles import ProfileManager
        pm = ProfileManager(self.install_dir, self.config, self.hardware)
        profile = pm.load(current_profile_name) or {}
        return self.deploy_module(name, profile)

    def disable(self, name: str) -> Tuple[bool, str]:
        module_dir = self.modules_dir / name
        if not module_dir.exists():
            return False, f"Module '{name}' not found"

        meta = self._load_meta(name)
        mod_type = meta.get("type", "native")

        if mod_type in ("native", "both"):
            service = meta.get("service", f"aetherium-{name}")
            try:
                subprocess.run(["systemctl", "stop", service], check=False, timeout=15)
                subprocess.run(["systemctl", "disable", service], check=False, timeout=10)
                return True, "stopped"
            except Exception as e:
                return False, str(e)

        elif mod_type in ("docker", "container"):
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
        update_script = self.modules_dir / name / "update.sh"
        if update_script.exists():
            return self._run_script(update_script, name, {})
        return False, "no update script"

    def _run_script(self, script: Path, module_name: str,
                    profile: Dict, env: Optional[Dict] = None) -> Tuple[bool, str]:
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
        env: Dict[str, str] = {}
        net = profile.get("network", {})
        env["AP_INTERFACE"]    = net.get("ap_interface") or "wlan0"
        env["MESH_INTERFACE"]  = net.get("mesh_interface") or "wlan0"
        env["UPLINK_INTERFACE"] = net.get("uplink_interface") or "eth0"
        env["HOTSPOT_SUBNET"]  = net.get("hotspot_subnet") or "192.168.42.0/24"
        env["HOTSPOT_IP"]      = net.get("hotspot_ip") or "192.168.42.1"

        hs = profile.get("hotspot", {})
        env["HOTSPOT_SSID"]     = hs.get("ssid") or "Aetherium"
        env["HOTSPOT_CHANNEL"]  = str(hs.get("channel") or 6)
        env["HOTSPOT_BAND"]     = hs.get("band") or "2.4GHz"
        env["HOTSPOT_PASSWORD"] = hs.get("password") or ""
        env["HOTSPOT_HIDDEN"]   = "1" if hs.get("hidden") else "0"
        env["CAPTIVE_PORTAL"]   = "1" if hs.get("captive_portal", True) else "0"

        node = profile.get("node", {})
        # NODE_NAME: profile → config → system hostname
        env["NODE_NAME"]    = (node.get("name") or
                               self.config.get("node.name") or
                               os.uname().nodename or
                               "aetherium-node")
        env["NODE_PROFILE"] = node.get("profile") or "relay"

        rns = profile.get("reticulum", {})
        env["RNS_ENABLED"]    = "1" if rns.get("enabled") else "0"
        env["RNS_CONFIG_DIR"] = rns.get("config_dir") or "/etc/reticulum"

        bat = profile.get("batman_adv", {})
        env["BATMAN_ENABLED"]    = "1" if bat.get("enabled") else "0"
        env["BATMAN_INTERFACE"]  = bat.get("interface") or env["MESH_INTERFACE"]
        env["BATMAN_GW_MODE"]    = bat.get("gw_mode") or "off"

        rnode = profile.get("rnode", {})
        env["RNODE_PORT"]     = rnode.get("port") or ""
        env["RNODE_FREQ"]     = str(rnode.get("frequency") or 915000000)
        env["RNODE_BW"]       = str(rnode.get("bandwidth") or 125000)
        env["RNODE_SF"]       = str(rnode.get("sf") or 7)
        env["RNODE_TX_POWER"] = str(rnode.get("tx_power") or 17)

        lte = profile.get("lte", {})
        env["LTE_APN"]     = lte.get("apn") or "auto"
        env["LTE_ROAMING"] = "1" if lte.get("roaming") else "0"

        power = profile.get("power", {})
        env["POWER_MODE"]         = power.get("mode") or "balanced"
        env["DISABLE_HDMI"]       = "1" if power.get("disable_hdmi") else "0"
        env["DISABLE_LEDS"]       = "1" if power.get("disable_leds") else "0"
        env["DISABLE_BLUETOOTH"]  = "1" if power.get("disable_bluetooth") else "0"

        # Hardware-detected regulatory domain and LoRa frequency
        hw_cc = self.hardware.regulatory_domain()
        env["REGULATORY_DOMAIN"]  = hw_cc
        if not rnode.get("frequency") and hw_cc:
            env["RNODE_FREQ"] = str(self.hardware.lora_frequency_for_region(hw_cc))

        return env


def _which(binary: str) -> bool:
    import shutil
    return shutil.which(binary) is not None
