> **Proprietary and confidential.** Copyright (c) 2026 Grange Dev Group. All rights reserved. This is not open source: you may not use, copy, build, modify, share, recreate or re-implement this code, or use it to train or prompt AI systems, even if you can see it. See [LICENSE](LICENSE).

# Mst-PI-Station

**Resilient Mesh Communications Stack for Field Deployments**

Mst-PI-Station installs on a Debian, Ubuntu, Arch or Fedora Linux system and turns it into a portable communications node that keeps working without the internet. Works on Raspberry Pi 4/5, ARM single-board computers, and x86_64 hardware.

---

## Quick Start

```bash
sudo bash install.sh --profile relay
```

### Profiles

```bash
mstpistation deploy relay          # persistent mesh relay + LoRa
mstpistation deploy field-node     # portable field comms node
mstpistation deploy hotspot        # Wi-Fi hotspot with local services
mstpistation deploy mesh-hub       # full community hub
mstpistation deploy emergency      # minimal emergency node
mstpistation deploy lte-gateway    # LTE uplink gateway
mstpistation deploy solar-relay    # low-power solar relay
mstpistation deploy local-services # offline content server
```

---

## What it does

Mst-PI-Station sets up and configures:

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
sudo mstpistation deploy relay

# Node status
mstpistation status
mstpistation status --json
mstpistation status --watch        # live view

# Module management
mstpistation module list
sudo mstpistation module enable syncthing
sudo mstpistation module disable kiwix

# Configuration
mstpistation config show
sudo mstpistation config set node.name my-relay
mstpistation config get hotspot.ssid
sudo mstpistation config edit      # open in $EDITOR

# Hardware
mstpistation hardware show
sudo mstpistation hardware detect  # re-detect

# Fleet
mstpistation fleet list            # list mesh peers

# Logs
mstpistation logs                  # all services
mstpistation logs reticulum        # specific service
mstpistation logs reticulum -f     # follow

# Updates
mstpistation update --check
sudo mstpistation update
```

---

## Directory Layout

```
/opt/mstpistation/        Installation
/etc/mstpistation/        Configuration (edit these)
  mstpistation.yaml       Main config
  hardware.yaml        Auto-detected hardware
  reticulum/           Reticulum config
  hostapd/             hostapd config
  dnsmasq/             dnsmasq config
/var/lib/mstpistation/    Persistent data
/var/log/mstpistation/    Logs
/var/run/mstpistation/    Runtime state (status.json, peers.json)
```

---

## Hardware Requirements

| Hardware | Minimum | Recommended |
|---|---|---|
| SBC | Raspberry Pi 3 | Raspberry Pi 5 |
| RAM | 512MB | 2GB+ |
| Storage | 8GB | 32GB |
| Wi-Fi | 1 adapter | 2 adapters (one for AP, one for mesh) |
| LoRa |, | RNode-compatible USB device |
| LTE |, | Quectel EC25 or Huawei E3372 |

Supported architectures: **aarch64, armv7l, x86_64**

---

## Source Dependencies

Mst-PI-Station integrates these open-source projects:

- [Reticulum](https://reticulum.network), encrypted mesh transport
- [LXMF](https://github.com/markqvist/LXMF), messaging over Reticulum
- [NomadNet](https://github.com/markqvist/NomadNet), mesh node pages
- [Sideband](https://github.com/markqvist/Sideband), mobile Reticulum client
- [batman-adv](https://www.open-mesh.org/projects/batman-adv), L2 mesh
- [RNode Firmware](https://github.com/markqvist/RNode_Firmware), LoRa firmware
- [Meshtastic](https://meshtastic.org), LoRa mesh (standalone)
- [OpenWrt](https://openwrt.org), router integration

---

## License

MIT, See LICENSE file.
