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
        """Load and resolve a profile.

        Resolution order (later wins):
          1. profile YAML — the role definition, identical on every device
          2. site + unified hardware config from ``Config.merged()``
          3. runtime interface resolution — turns "auto"/empty into real ifaces

        Site config is merged for every top-level section EXCEPT ``modules``:
        a profile's ``modules`` is an ordered deploy *list*, while the site
        ``modules`` is a per-module options *dict* — deep-merging the two would
        clobber the deploy list. (Per-module enable/disable is honoured by the
        deployer via ``Config.module_enabled``/``module_disabled``.)

        Interface resolution runs LAST so a site value of "auto" can never
        overwrite an interface we already resolved from detected hardware.
        """
        profile_file = self.profiles_dir / f"{name}.yaml"
        if not profile_file.exists():
            return None

        with open(profile_file) as f:
            profile = yaml.safe_load(f) or {}

        # 2. Merge site + unified hardware config over the profile (site wins),
        #    preserving the profile's ordered 'modules' deploy list.
        deploy_modules = profile.get("modules")
        site_cfg = self.config.merged()
        _deep_merge(profile, {k: v for k, v in site_cfg.items() if k != "modules"})
        if deploy_modules is not None:
            profile["modules"] = deploy_modules

        # 3. Resolve interfaces from detected hardware (model-agnostic). Single-
        #    radio devices fall back to sharing the AP radio for mesh.
        suggested = self.hardware.suggested_interfaces()
        net = profile.setdefault("network", {})
        if net.get("ap_interface") in (None, "", "auto"):
            net["ap_interface"] = suggested["ap"] or "wlan0"
        if net.get("mesh_interface") in (None, "", "auto"):
            net["mesh_interface"] = suggested["mesh"] or net["ap_interface"]
        if net.get("uplink_interface") in (None, "", "auto"):
            net["uplink_interface"] = suggested["uplink"] or "eth0"

        # Inject hardware-detected RNode device if the profile didn't pin one.
        if suggested["first_rnode"]:
            rn = profile.setdefault("rnode", {})
            if not rn.get("port"):
                rn["port"] = suggested["first_rnode"]

        return profile

    def suggest(self) -> str:
        """Return the recommended profile name based on current hardware."""
        return self.hardware.suggest_profile()

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
