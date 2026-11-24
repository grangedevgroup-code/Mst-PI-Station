#!/usr/bin/env python3
"""Emergency alert listener — receives LXMF broadcasts tagged as emergency alerts."""
import os
import sys
import time
import subprocess
import logging

MSTPISTATION_DIR = os.environ.get("MSTPISTATION_DIR", "/opt/mstpistation")
sys.path.insert(0, os.path.join(MSTPISTATION_DIR, "venv/lib"))

logging.basicConfig(level=logging.INFO, format="[emergency/listener] %(message)s")
LOG = logging.getLogger("emergency-listener")

try:
    import RNS
    import LXMF
except ImportError:
    LOG.error("Reticulum/LXMF not available")
    sys.exit(1)

IDENTITY_PATH = "/var/lib/mstpistation/emergency-listener-identity"
ALERT_LOG = "/var/log/mstpistation/emergency/alerts.log"

os.makedirs(os.path.dirname(ALERT_LOG), exist_ok=True)


def delivery_callback(message):
    title = message.title_as_string() if message.title else ""
    content = message.content_as_string() if message.content else ""

    if "EMERGENCY" not in title.upper() and not content.startswith("[EMERGENCY"):
        return

    sender = RNS.prettyhexrep(message.source_hash) if message.source_hash else "unknown"
    alert_text = f"EMERGENCY ALERT from {sender}: {content}"
    LOG.warning(alert_text)

    # Append to alert log
    with open(ALERT_LOG, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ')} {alert_text}\n")

    # Wall broadcast to all logged-in users
    try:
        subprocess.run(["wall", alert_text], check=False, timeout=5)
    except Exception:
        pass

    # Flash Pi ACT LED if available
    led_trigger = "/sys/class/leds/ACT/trigger"
    if os.path.exists(led_trigger):
        try:
            with open(led_trigger, "w") as f:
                f.write("timer")
        except Exception:
            pass


def main():
    RNS.Reticulum()

    if os.path.exists(IDENTITY_PATH):
        identity = RNS.Identity.from_file(IDENTITY_PATH)
    else:
        identity = RNS.Identity()
        identity.to_file(IDENTITY_PATH)

    router = LXMF.LXMRouter(storagepath="/var/lib/mstpistation/lxmf-emergency-listener")
    router.register_delivery_identity(identity, display_name="Emergency Listener")
    router.register_delivery_callback(delivery_callback)

    LOG.info("Emergency listener active")
    while True:
        time.sleep(5)


if __name__ == "__main__":
    main()
