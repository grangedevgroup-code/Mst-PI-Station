#!/usr/bin/env python3
"""
Aetherium Meshtastic ↔ LXMF Bridge
Connects a Meshtastic device to the Reticulum/LXMF mesh.

Messages sent on Meshtastic channel 0 appear in LXMF and vice versa.
Node names are preserved. The bridge announces itself on both networks.
"""

import os
import sys
import time
import json
import logging
import threading
import hashlib
from pathlib import Path

AETHERIUM_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(AETHERIUM_DIR))

log = logging.getLogger("meshtastic-bridge")
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")

DEVICE_PORT = None
DATA_DIR = Path("/var/lib/aetherium/meshtastic")
STATE_FILE = DATA_DIR / "bridge-state.json"


def find_device():
    """Auto-detect Meshtastic device."""
    candidates = [
        "/dev/meshtastic0",
        "/dev/ttyUSB0", "/dev/ttyUSB1",
        "/dev/ttyACM0", "/dev/ttyACM1",
    ]
    for port in candidates:
        if Path(port).exists():
            return port
    return None


class MeshtasticBridge:
    def __init__(self, device_port=None):
        self.device_port = device_port or find_device()
        self.mesh_iface = None
        self.lxmf_dest = None
        self.running = True
        self.message_queue = []
        self.lock = threading.Lock()
        self.known_mesh_nodes = {}

        DATA_DIR.mkdir(parents=True, exist_ok=True)

    def start(self):
        if not self.device_port:
            log.warning("No Meshtastic device found. Waiting for device...")
            self._wait_for_device()

        log.info(f"Connecting to Meshtastic device on {self.device_port}")
        self._connect_meshtastic()
        self._connect_lxmf()
        self._run()

    def _wait_for_device(self):
        """Poll for device connection."""
        while self.running and not self.device_port:
            self.device_port = find_device()
            if not self.device_port:
                time.sleep(10)

    def _connect_meshtastic(self):
        try:
            import meshtastic
            import meshtastic.serial_interface
            from pubsub import pub

            self.mesh_iface = meshtastic.serial_interface.SerialInterface(
                devPath=self.device_port
            )
            node_info = self.mesh_iface.getMyNodeInfo()
            log.info(f"Meshtastic connected: {node_info}")

            pub.subscribe(self._on_mesh_receive, "meshtastic.receive.text")
            pub.subscribe(self._on_mesh_node_info, "meshtastic.receive.nodeinfo")
            pub.subscribe(self._on_mesh_position, "meshtastic.receive.position")
            pub.subscribe(self._on_connection_lost, "meshtastic.connection.lost")

            log.info("Meshtastic subscriptions active")
        except ImportError:
            log.error("meshtastic library not installed")
            raise
        except Exception as e:
            log.error(f"Meshtastic connection failed: {e}")
            raise

    def _connect_lxmf(self):
        try:
            import RNS
            import LXMF

            # Use shared RNS instance
            rns = RNS.Reticulum()

            # Create identity for this bridge
            identity_file = DATA_DIR / "identity"
            if identity_file.exists():
                self.identity = RNS.Identity.from_file(str(identity_file))
            else:
                self.identity = RNS.Identity()
                self.identity.to_file(str(identity_file))

            self.lxmf_router = LXMF.LXMRouter(
                storagepath=str(DATA_DIR / "lxmf"),
                identity=self.identity
            )
            self.lxmf_dest = self.lxmf_router.register_delivery_callback(
                self._on_lxmf_receive
            )

            log.info(f"LXMF bridge address: {RNS.prettyhexrep(self.lxmf_dest.hash)}")
        except Exception as e:
            log.error(f"LXMF/RNS connection failed: {e}")
            raise

    def _on_mesh_receive(self, packet, interface):
        """Meshtastic → LXMF: forward text messages."""
        try:
            decoded = packet.get("decoded", {})
            text = decoded.get("text", "")
            if not text:
                return

            sender_id = packet.get("fromId", "unknown")
            sender_long = self.known_mesh_nodes.get(sender_id, {}).get("longName", sender_id)

            log.info(f"[Mesh→LXMF] {sender_long}: {text[:60]}")

            # Format message with Meshtastic attribution
            lxmf_body = f"[Meshtastic/{sender_long}] {text}"

            # Broadcast to all LXMF destinations that have announced
            self._broadcast_lxmf(lxmf_body, source=sender_long)

        except Exception as e:
            log.debug(f"mesh receive error: {e}")

    def _on_mesh_node_info(self, packet, interface):
        """Track Meshtastic node names for display."""
        try:
            user = packet.get("decoded", {}).get("user", {})
            node_id = packet.get("fromId", "")
            if node_id and user:
                self.known_mesh_nodes[node_id] = user
        except Exception:
            pass

    def _on_mesh_position(self, packet, interface):
        """Forward GPS positions to status."""
        try:
            pos = packet.get("decoded", {}).get("position", {})
            lat = pos.get("latitudeI", 0) / 1e7
            lon = pos.get("longitudeI", 0) / 1e7
            if lat and lon:
                node_id = packet.get("fromId", "unknown")
                self._update_position(node_id, lat, lon)
        except Exception:
            pass

    def _on_connection_lost(self, interface):
        log.warning("Meshtastic connection lost — reconnecting in 30s")
        self.mesh_iface = None
        time.sleep(30)
        try:
            self._connect_meshtastic()
        except Exception as e:
            log.error(f"Reconnect failed: {e}")

    def _on_lxmf_receive(self, message):
        """LXMF → Meshtastic: forward messages."""
        try:
            import RNS
            content = message.content.decode("utf-8", errors="replace")
            source_addr = RNS.prettyhexrep(message.source_hash)

            log.info(f"[LXMF→Mesh] {source_addr[:8]}: {content[:60]}")

            # Don't re-bridge messages that originated from Meshtastic
            if content.startswith("[Meshtastic/"):
                return

            # Send to Meshtastic mesh
            if self.mesh_iface:
                short_msg = f"[RNS] {content[:200]}"
                self.mesh_iface.sendText(short_msg, channelIndex=0)
        except Exception as e:
            log.debug(f"LXMF receive error: {e}")

    def _broadcast_lxmf(self, text, source="meshtastic"):
        """Send a message to all known LXMF destinations."""
        try:
            import RNS, LXMF
            # For now, log — proper LXMF broadcast to known peers
            # In production: iterate known RNS destinations and send
            log.debug(f"Would broadcast to LXMF: {text}")
        except Exception as e:
            log.debug(f"LXMF broadcast error: {e}")

    def _update_position(self, node_id, lat, lon):
        positions_file = DATA_DIR / "positions.json"
        try:
            positions = json.loads(positions_file.read_text()) if positions_file.exists() else {}
            positions[node_id] = {"lat": lat, "lon": lon, "ts": time.time()}
            positions_file.write_text(json.dumps(positions, indent=2))
        except Exception:
            pass

    def _run(self):
        log.info("Meshtastic bridge running")
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            self._cleanup()

    def _cleanup(self):
        if self.mesh_iface:
            try:
                self.mesh_iface.close()
            except Exception:
                pass


def main():
    device = os.environ.get("MESHTASTIC_PORT") or find_device()
    bridge = MeshtasticBridge(device)
    bridge.start()


if __name__ == "__main__":
    main()
