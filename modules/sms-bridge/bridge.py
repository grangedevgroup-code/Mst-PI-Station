#!/usr/bin/env python3
"""SMS ↔ LXMF bridge via ModemManager DBus API."""
import os
import sys
import time
import json
import logging
import subprocess
import threading

AETHERIUM_DIR = os.environ.get("AETHERIUM_DIR", "/opt/aetherium")
sys.path.insert(0, os.path.join(AETHERIUM_DIR, "venv/lib"))

logging.basicConfig(level=logging.INFO, format="[sms-bridge] %(message)s")
LOG = logging.getLogger("sms-bridge")

SMS_LOG = "/var/log/aetherium/sms-bridge/messages.jsonl"
IDENTITY_PATH = "/var/lib/aetherium/sms-bridge-identity"
os.makedirs(os.path.dirname(SMS_LOG), exist_ok=True)

try:
    import RNS
    import LXMF
    HAS_RNS = True
except ImportError:
    LOG.warning("Reticulum/LXMF not available — SMS will log only")
    HAS_RNS = False


def mmcli(*args):
    """Run mmcli and return output."""
    try:
        result = subprocess.run(
            ["mmcli"] + list(args),
            capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip()
    except Exception as e:
        LOG.debug("mmcli error: %s", e)
        return ""


def get_modem_index():
    output = mmcli("-L")
    for line in output.splitlines():
        if "/Modem/" in line:
            parts = line.split("/Modem/")
            if len(parts) > 1:
                idx = parts[1].split()[0].strip()
                return idx
    return None


def list_sms_messages(modem_idx):
    output = mmcli("-m", modem_idx, "--messaging-list-sms")
    indices = []
    for line in output.splitlines():
        if "/SMS/" in line:
            parts = line.split("/SMS/")
            if len(parts) > 1:
                idx = parts[1].split()[0].strip()
                indices.append(idx)
    return indices


def read_sms(modem_idx, sms_idx):
    output = mmcli("-m", modem_idx, "-s", sms_idx)
    msg = {"from": "", "text": "", "timestamp": ""}
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("number:"):
            msg["from"] = line.split(":", 1)[1].strip()
        elif line.startswith("text:"):
            msg["text"] = line.split(":", 1)[1].strip()
        elif line.startswith("timestamp:"):
            msg["timestamp"] = line.split(":", 1)[1].strip()
    return msg


def delete_sms(modem_idx, sms_idx):
    mmcli("-m", modem_idx, "--messaging-delete-sms", sms_idx)


def send_sms(modem_idx, number, text):
    output = mmcli("-m", modem_idx,
                   "--messaging-create-sms", f"text='{text}',number={number}")
    for line in output.splitlines():
        if "/SMS/" in line:
            parts = line.split("/SMS/")
            if len(parts) > 1:
                sms_idx = parts[1].split()[0].strip()
                mmcli("-m", modem_idx, "-s", sms_idx, "--send")
                mmcli("-m", modem_idx, "--messaging-delete-sms", sms_idx)
                return True
    return False


def log_message(direction, number, text):
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dir": direction,
        "number": number,
        "text": text,
    }
    with open(SMS_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")


class SMSBridge:
    def __init__(self):
        self.modem_idx = None
        self.router = None
        self.source = None
        if HAS_RNS:
            self._init_lxmf()

    def _init_lxmf(self):
        RNS.Reticulum()
        if os.path.exists(IDENTITY_PATH):
            identity = RNS.Identity.from_file(IDENTITY_PATH)
        else:
            identity = RNS.Identity()
            identity.to_file(IDENTITY_PATH)
        self.router = LXMF.LXMRouter(storagepath="/var/lib/aetherium/lxmf-sms")
        self.source = self.router.register_delivery_identity(
            identity, display_name="SMS Bridge"
        )
        self.router.register_delivery_callback(self._on_lxmf_message)
        LOG.info("LXMF identity ready: %s", RNS.prettyhexrep(identity.hash))

    def _on_lxmf_message(self, message):
        """Forward LXMF → SMS. Content format: +15551234567 Your message here"""
        content = message.content_as_string() if message.content else ""
        parts = content.strip().split(" ", 1)
        if len(parts) < 2 or not parts[0].startswith("+"):
            LOG.warning("LXMF→SMS: bad format (need: +number message). Got: %s", content[:60])
            return
        number, text = parts[0], parts[1]
        if self.modem_idx:
            ok = send_sms(self.modem_idx, number, text)
            log_message("out", number, text)
            LOG.info("SMS sent to %s: %s", number, "OK" if ok else "FAILED")

    def poll_sms(self):
        """Poll ModemManager for incoming SMS and forward to LXMF mesh."""
        if not self.modem_idx:
            return
        indices = list_sms_messages(self.modem_idx)
        for sms_idx in indices:
            msg = read_sms(self.modem_idx, sms_idx)
            if not msg.get("text"):
                continue
            log_message("in", msg["from"], msg["text"])
            LOG.info("SMS from %s: %s", msg["from"], msg["text"][:60])

            if HAS_RNS and self.router and self.source:
                try:
                    lxm = LXMF.LXMessage(
                        LXMF.LXMessage.BROADCAST,
                        self.source,
                        None,
                        title=f"SMS from {msg['from']}",
                        content=msg["text"],
                        desired_method=LXMF.LXMessage.PROPAGATED,
                    )
                    self.router.handle_outbound(lxm)
                except Exception as e:
                    LOG.error("LXMF forward failed: %s", e)

            delete_sms(self.modem_idx, sms_idx)

    def run(self):
        LOG.info("SMS bridge starting")
        while True:
            if not self.modem_idx:
                self.modem_idx = get_modem_index()
                if self.modem_idx:
                    LOG.info("Modem found: %s", self.modem_idx)
                else:
                    LOG.debug("No modem found — retrying in 30s")
                    time.sleep(30)
                    continue
            try:
                self.poll_sms()
            except Exception as e:
                LOG.error("Poll error: %s", e)
                self.modem_idx = None
            time.sleep(10)


if __name__ == "__main__":
    SMSBridge().run()
