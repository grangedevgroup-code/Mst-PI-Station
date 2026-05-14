#!/usr/bin/env bash
# Hardware detection — produces /etc/aetherium/hardware.yaml
# Sourced by install.sh — sets HW_MODEL, HW_ARCH, etc.

HW_MODEL="generic"
HW_ARCH=""
HW_CPU_CORES=1
HW_RAM_MB=0
HW_IS_PI=0
HW_PI_REVISION=""

detect_hardware() {
    HW_ARCH=$(uname -m)
    HW_CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    HW_RAM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)

    # Raspberry Pi detection
    if [[ -f /proc/device-tree/model ]]; then
        local model
        model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "")
        case "${model}" in
            *"Raspberry Pi 5"*)  HW_MODEL="rpi5"; HW_IS_PI=1 ;;
            *"Raspberry Pi 4"*)  HW_MODEL="rpi4"; HW_IS_PI=1 ;;
            *"Raspberry Pi 3"*)  HW_MODEL="rpi3"; HW_IS_PI=1 ;;
            *"Raspberry Pi 2"*)  HW_MODEL="rpi2"; HW_IS_PI=1 ;;
            *"Raspberry Pi Zero 2"*) HW_MODEL="rpizero2"; HW_IS_PI=1 ;;
            *"Raspberry Pi Zero"*)   HW_MODEL="rpizero";  HW_IS_PI=1 ;;
            *"Raspberry Pi"*)    HW_MODEL="rpi"; HW_IS_PI=1 ;;
            *"Orange Pi"*)       HW_MODEL="orangepi" ;;
            *"Rock Pi"*)         HW_MODEL="rockpi" ;;
            *"ODROID"*)          HW_MODEL="odroid" ;;
        esac
        HW_PI_REVISION="${model}"
    fi

    if [[ "${HW_MODEL}" == "generic" ]]; then
        # DMI-based detection for x86_64
        if [[ -f /sys/class/dmi/id/product_name ]]; then
            local dmi
            dmi=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
            HW_MODEL="generic-${HW_ARCH}"
            [[ -n "${dmi}" ]] && HW_PI_REVISION="${dmi}"
        else
            HW_MODEL="generic-${HW_ARCH}"
        fi
    fi

    # Network interface discovery
    detect_interfaces

    # Serial device discovery (RNode, modems)
    detect_serial

    # Storage
    HW_STORAGE_GB=$(df -BG / 2>/dev/null | awk 'NR==2{gsub(/G/,"",$2); print $2}' || echo 0)

    write_hardware_yaml
    log "Hardware: ${HW_PI_REVISION:-${HW_MODEL}} | ${HW_CPU_CORES} cores | ${HW_RAM_MB}MB RAM | ${HW_ARCH}"
}

detect_interfaces() {
    HW_WIFI_INTERFACES=()
    HW_ETH_INTERFACES=()
    HW_WWAN_INTERFACES=()

    # Find wireless interfaces
    for iface in /sys/class/net/*/; do
        local name
        name=$(basename "${iface}")
        if [[ -d "${iface}/wireless" ]] || [[ -d "/sys/class/ieee80211" ]] && \
           ls /sys/class/ieee80211/*/device/net/ 2>/dev/null | grep -q "^${name}$"; then
            HW_WIFI_INTERFACES+=("${name}")
        elif [[ "${name}" =~ ^(eth|en|eno|enp|ens)[0-9] ]]; then
            HW_ETH_INTERFACES+=("${name}")
        elif [[ "${name}" =~ ^(wwan|usb|ppp)[0-9] ]]; then
            HW_WWAN_INTERFACES+=("${name}")
        fi
    done

    # Get wifi capabilities via iw
    HW_WIFI_AP_CAPABLE=()
    HW_WIFI_MESH_CAPABLE=()
    if command -v iw &>/dev/null; then
        for wiface in "${HW_WIFI_INTERFACES[@]}"; do
            local phy
            phy=$(iw dev "${wiface}" info 2>/dev/null | awk '/wiphy/{print "phy"$2}' || echo "")
            if [[ -n "${phy}" ]]; then
                local caps
                caps=$(iw phy "${phy}" info 2>/dev/null || echo "")
                echo "${caps}" | grep -q "AP$\|AP/VLAN" && HW_WIFI_AP_CAPABLE+=("${wiface}")
                echo "${caps}" | grep -q "mesh point\|IBSS" && HW_WIFI_MESH_CAPABLE+=("${wiface}")
            fi
        done
    fi
}

detect_serial() {
    HW_SERIAL_DEVICES=()
    HW_RNODE_DEVICES=()
    HW_LTE_DEVICES=()

    for dev in /dev/ttyUSB* /dev/ttyACM* /dev/ttyAMA* /dev/serial/by-id/*; do
        [[ -e "${dev}" ]] || continue
        local realdev
        realdev=$(readlink -f "${dev}" 2>/dev/null || echo "${dev}")
        HW_SERIAL_DEVICES+=("${realdev}")

        # Identify known devices by USB vendor:product
        local vid pid
        local sysdev
        sysdev=$(basename "${realdev}")
        if [[ -f "/sys/class/tty/${sysdev}/device/idVendor" ]]; then
            vid=$(cat "/sys/class/tty/${sysdev}/device/idVendor" 2>/dev/null || echo "")
            pid=$(cat "/sys/class/tty/${sysdev}/device/idProduct" 2>/dev/null || echo "")
            case "${vid}:${pid}" in
                # RNode / Rakwireless
                1a86:55d4|10c4:ea60|0403:6001)
                    HW_RNODE_DEVICES+=("${realdev}")
                    ;;
                # Quectel LTE modems
                2c7c:0125|2c7c:0121|2c7c:0306)
                    HW_LTE_DEVICES+=("${realdev}")
                    ;;
                # Huawei
                12d1:1001|12d1:14fe|12d1:1506)
                    HW_LTE_DEVICES+=("${realdev}")
                    ;;
            esac
        fi
    done
}

write_hardware_yaml() {
    local out="/etc/aetherium/hardware.yaml"
    mkdir -p "$(dirname "${out}")"

    # Build YAML lists
    local wifi_list eth_list wwan_list serial_list rnode_list lte_list
    wifi_list=$(printf '    - "%s"\n' "${HW_WIFI_INTERFACES[@]:-}")
    eth_list=$(printf '    - "%s"\n'  "${HW_ETH_INTERFACES[@]:-}")
    wwan_list=$(printf '    - "%s"\n' "${HW_WWAN_INTERFACES[@]:-}")
    serial_list=$(printf '    - "%s"\n' "${HW_SERIAL_DEVICES[@]:-}")
    rnode_list=$(printf '    - "%s"\n' "${HW_RNODE_DEVICES[@]:-}")
    lte_list=$(printf '    - "%s"\n' "${HW_LTE_DEVICES[@]:-}")

    cat > "${out}" << YAML
# Auto-generated by Aetherium hardware detection — do not edit manually
# Re-detect: aetherium hardware detect

model: "${HW_MODEL}"
revision: "${HW_PI_REVISION:-}"
arch: "${HW_ARCH}"
is_pi: ${HW_IS_PI}
cpu_cores: ${HW_CPU_CORES}
ram_mb: ${HW_RAM_MB}
storage_gb: ${HW_STORAGE_GB:-0}
kernel: "$(uname -r)"
detected_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

interfaces:
  wifi:
${wifi_list:-    []}
  ethernet:
${eth_list:-    []}
  wwan:
${wwan_list:-    []}
  serial:
${serial_list:-    []}

devices:
  rnode:
${rnode_list:-    []}
  lte_modem:
${lte_list:-    []}

capabilities:
  wifi_ap: ${#HW_WIFI_AP_CAPABLE[@]}
  wifi_mesh: ${#HW_WIFI_MESH_CAPABLE[@]}
  has_rnode: $([[ ${#HW_RNODE_DEVICES[@]} -gt 0 ]] && echo true || echo false)
  has_lte: $([[ ${#HW_LTE_DEVICES[@]} -gt 0 ]] && echo true || echo false)
  gpio: $([[ -d /sys/class/gpio ]] && echo true || echo false)
YAML

    chmod 644 "${out}"
}
