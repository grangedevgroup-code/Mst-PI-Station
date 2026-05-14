#!/usr/bin/env python3
"""Emergency broadcast — sends an LXMF message to all known mesh peers."""
import sys
import os
import time
import json
import argparse
import logging

AETHERIUM_DIR = os.environ.get("AETHERIUM_DIR", "/opt/aetherium")
sys.path.insert(0, os.path.join(AETHERIUM_DIR, "venv/lib"))

try:
    import RNS
    import LXMF
except ImportError:
    print("ERROR: Reticulum/LXMF not available. Is Aetherium installed?", file=sys.stderr)
    sys.exit(1)

LOG = logging.getLogger("emergency")
IDENTITY_PATH = "/var/lib/aetherium/emergency-identity"
PEERS_FILE = "/var/run/aetherium/status.json"


def load_peers():
    if not os.path.exists(PEERS_FILE):
        return []
    try:
        status = json.loads(open(PEERS_FILE).read())
        return status.get("batman_peers", []) + status.get("rns_peers", [])
    except Exception:
        return []


def broadcast(message: str, retransmit: int = 3, interval: int = 30):
    RNS.Reticulum()
    if os.path.exists(IDENTITY_PATH):
        identity = RNS.Identity.from_file(IDENTITY_PATH)
    else:
        identity = RNS.Identity()
        identity.to_file(IDENTITY_PATH)

    router = LXMF.LXMRouter(storagepath="/var/lib/aetherium/lxmf-emergency")
    source = router.register_delivery_identity(identity, display_name="EMERGENCY")

    node_name = os.environ.get("NODE_NAME", "Aetherium Node")
    full_message = f"[EMERGENCY from {node_name}] {message}"

    # Broadcast via LXMF propagation (reaches all nodes on network)
    for attempt in range(retransmit):
        try:
            lxm = LXMF.LXMessage(
                LXMF.LXMessage.BROADCAST,
                source,
                None,
                title="EMERGENCY ALERT",
                content=full_message,
                desired_method=LXMF.LXMessage.PROPAGATED,
            )
            router.handle_outbound(lxm)
            print(f"[emergency] Broadcast sent (attempt {attempt + 1}/{retransmit})")
        except Exception as e:
            print(f"[emergency] Broadcast attempt {attempt + 1} failed: {e}", file=sys.stderr)

        if attempt < retransmit - 1:
            time.sleep(interval)

    LOG.info("Emergency broadcast complete: %s", message)


def main():
    parser = argparse.ArgumentParser(description="Aetherium emergency broadcast")
    parser.add_argument("message", nargs="+", help="Emergency message text")
    parser.add_argument("--retransmit", type=int, default=3,
                        help="Number of times to retransmit (default: 3)")
    parser.add_argument("--interval", type=int, default=30,
                        help="Seconds between retransmits (default: 30)")
    args = parser.parse_args()

    msg = " ".join(args.message)
    print(f"[emergency] Sending: {msg}")
    broadcast(msg, retransmit=args.retransmit, interval=args.interval)


if __name__ == "__main__":
    main()
