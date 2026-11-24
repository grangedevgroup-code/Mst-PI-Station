#!/usr/bin/env python3
"""OTA update watcher — monitors Syncthing share for signed update bundles."""
import os
import sys
import time
import json
import hashlib
import tarfile
import logging
import subprocess
import shutil
import glob

MSTPISTATION_DIR = os.environ.get("MSTPISTATION_DIR", "/opt/mstpistation")
INCOMING_DIR = "/var/lib/mstpistation/ota/incoming"
APPLIED_DIR = "/var/lib/mstpistation/ota/applied"
OTA_LOG = "/var/log/mstpistation/ota/updates.log"
KEYRING = "/etc/mstpistation/ota/trusted-keys.gpg"

logging.basicConfig(level=logging.INFO, format="[ota] %(message)s")
LOG = logging.getLogger("ota")
os.makedirs(os.path.dirname(OTA_LOG), exist_ok=True)


def log_event(event: str, bundle: str, status: str):
    entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ"), "bundle": bundle,
             "event": event, "status": status}
    with open(OTA_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")
    LOG.info("%s: %s [%s]", event, bundle, status)


def verify_signature(bundle_path: str) -> bool:
    sig_path = bundle_path + ".sig"
    if not os.path.exists(sig_path):
        LOG.warning("No signature file for %s — skipping", bundle_path)
        return False
    if not os.path.exists(KEYRING):
        LOG.warning("No trusted keyring at %s — skipping signature check", KEYRING)
        return False
    result = subprocess.run(
        ["gpg", "--no-default-keyring", "--keyring", KEYRING,
         "--verify", sig_path, bundle_path],
        capture_output=True, text=True
    )
    return result.returncode == 0


def apply_bundle(bundle_path: str) -> bool:
    """Extract and apply an Mst-PI-Station update bundle (.aeth-update = tar.gz)."""
    tmp_dir = f"/tmp/mstpistation-ota-{int(time.time())}"
    try:
        os.makedirs(tmp_dir, exist_ok=True)
        with tarfile.open(bundle_path, "r:gz") as tar:
            # Security: only extract to expected paths
            members = [m for m in tar.getmembers()
                       if not m.name.startswith("/") and ".." not in m.name]
            tar.extractall(tmp_dir, members=members)

        manifest_path = os.path.join(tmp_dir, "manifest.json")
        if not os.path.exists(manifest_path):
            LOG.error("Bundle missing manifest.json")
            return False

        manifest = json.loads(open(manifest_path).read())
        version = manifest.get("version", "unknown")
        LOG.info("Applying update: version %s", version)

        # Run the bundle's install script if present
        install_script = os.path.join(tmp_dir, "install.sh")
        if os.path.exists(install_script):
            os.chmod(install_script, 0o755)
            result = subprocess.run(
                ["bash", install_script],
                env={**os.environ, "MSTPISTATION_DIR": MSTPISTATION_DIR,
                     "UPDATE_VERSION": version},
                timeout=300,
            )
            if result.returncode != 0:
                LOG.error("Install script failed (exit %d)", result.returncode)
                return False

        # Copy files listed in manifest
        for src_rel, dest_abs in manifest.get("files", {}).items():
            src = os.path.join(tmp_dir, src_rel)
            if os.path.exists(src):
                os.makedirs(os.path.dirname(dest_abs), exist_ok=True)
                shutil.copy2(src, dest_abs)

        LOG.info("Update %s applied successfully", version)
        return True

    except Exception as e:
        LOG.error("Bundle apply failed: %s", e)
        return False
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def get_current_version() -> str:
    version_file = os.path.join(MSTPISTATION_DIR, "VERSION")
    if os.path.exists(version_file):
        return open(version_file).read().strip()
    return "0.0.0"


def already_applied(bundle_name: str) -> bool:
    applied_marker = os.path.join(APPLIED_DIR, bundle_name + ".applied")
    return os.path.exists(applied_marker)


def mark_applied(bundle_name: str):
    os.makedirs(APPLIED_DIR, exist_ok=True)
    open(os.path.join(APPLIED_DIR, bundle_name + ".applied"), "w").close()


def scan_and_apply():
    bundles = sorted(glob.glob(os.path.join(INCOMING_DIR, "*.aeth-update")))
    for bundle_path in bundles:
        bundle_name = os.path.basename(bundle_path)
        if already_applied(bundle_name):
            continue

        LOG.info("Found update bundle: %s", bundle_name)

        if not verify_signature(bundle_path):
            log_event("verify", bundle_name, "FAILED")
            continue

        log_event("apply_start", bundle_name, "OK")
        if apply_bundle(bundle_path):
            mark_applied(bundle_name)
            log_event("apply_done", bundle_name, "OK")
        else:
            log_event("apply_done", bundle_name, "FAILED")


def main():
    LOG.info("OTA watcher started — watching %s", INCOMING_DIR)
    LOG.info("Current version: %s", get_current_version())
    os.makedirs(INCOMING_DIR, exist_ok=True)
    while True:
        scan_and_apply()
        time.sleep(300)  # Check every 5 minutes


if __name__ == "__main__":
    main()
