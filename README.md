# Aetherium

**Resilient Mesh Communications Stack for Field Deployments**

Aetherium installs on top of any Debian/Ubuntu/Arch/Fedora Linux system and transforms it into a portable resilient communications node. Works on Raspberry Pi 4/5, ARM single-board computers, and x86_64 hardware.

---

## Quick Start

```bash
# One-command install
curl -fsSL https://get.aetherium.io/install | sudo bash

# Or from this repo
sudo bash install.sh --profile relay
```

### Profiles

```bash
aetherium deploy relay          # persistent mesh relay + LoRa
aetherium deploy field-node     # portable field comms node
aetherium deploy hotspot        # Wi-Fi hotspot with local services
aetherium deploy mesh-hub       # full community hub
aetherium deploy emergency      # minimal emergency node
aetherium deploy lte-gateway    # LTE uplink gateway
aetherium deploy solar-relay    # low-power solar relay
aetherium deploy local-services # offline content server
```

---

## What it does

Aetherium orchestrates and configures:

| Layer | Technology |
|---|---|
| Mesh networking | batman-adv (L2), Reticulum (application) |
| Wi-Fi AP | hostapd + dnsmasq |
| Encrypted messaging | Reticulum + LXMF + NomadNet |
| Long-range LoRa | RNode firmware + Reticulum RNodeInterface |
| Firewall / NAT | nftables |
| VPN tunnel | WireGuard (optional) |
| LTE backhaul | ModemManager + NetworkManager |
| File sync | Syncthing (container, optional) |
| Offline content | Kiwix (container, optional) |
| Voice comms | Mumble (container, optional) |
| Monitoring | Prometheus + Grafana (container, optional) |
| Dashboard | FastAPI + Alpine.js on port 8080 |

---

## CLI Reference

```bash
# Deploy a profile
sudo aetherium deploy relay

# Node status
aetherium status
aetherium status --json
aetherium status --watch        # live view

# Module management
aetherium module list
sudo aetherium module enable syncthing
sudo aetherium module disable kiwix

# Configuration
aetherium config show
sudo aetherium config set node.name my-relay
aetherium config get hotspot.ssid
sudo aetherium config edit      # open in $EDITOR

# Hardware
aetherium hardware show
sudo aetherium hardware detect  # re-detect

# Fleet
aetherium fleet list            # list mesh peers

# Logs
aetherium logs                  # all services
aetherium logs reticulum        # specific service
aetherium logs reticulum -f     # follow

# Updates
aetherium update --check
sudo aetherium update
```

---

## Directory Layout

```
/opt/aetherium/        Installation
/etc/aetherium/        Configuration (edit these)
  aetherium.yaml       Main config
  hardware.yaml        Auto-detected hardware
  reticulum/           Reticulum config
  hostapd/             hostapd config
  dnsmasq/             dnsmasq config
/var/lib/aetherium/    Persistent data
/var/log/aetherium/    Logs
/var/run/aetherium/    Runtime state (status.json, peers.json)
```

---

## Hardware Requirements

| Hardware | Minimum | Recommended |
|---|---|---|
| SBC | Raspberry Pi 3 | Raspberry Pi 5 |
| RAM | 512MB | 2GB+ |
| Storage | 8GB | 32GB |
| Wi-Fi | 1 adapter | 2 adapters (one for AP, one for mesh) |
| LoRa | — | RNode-compatible USB device |
| LTE | — | Quectel EC25 or Huawei E3372 |

Supported architectures: **aarch64, armv7l, x86_64**

---

## Source Dependencies

Aetherium integrates these open-source projects:

- [Reticulum](https://reticulum.network) — encrypted mesh transport
- [LXMF](https://github.com/markqvist/LXMF) — messaging over Reticulum
- [NomadNet](https://github.com/markqvist/NomadNet) — mesh node pages
- [Sideband](https://github.com/markqvist/Sideband) — mobile Reticulum client
- [batman-adv](https://www.open-mesh.org/projects/batman-adv) — L2 mesh
- [RNode Firmware](https://github.com/markqvist/RNode_Firmware) — LoRa firmware
- [Meshtastic](https://meshtastic.org) — LoRa mesh (standalone)
- [OpenWrt](https://openwrt.org) — router integration

---

## License

MIT — See LICENSE file.
