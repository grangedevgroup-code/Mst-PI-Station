#!/usr/bin/env bash
# Pre-flight checks — sourced by install.sh

PREFLIGHT_ERRORS=0
PREFLIGHT_WARNINGS=0

preflight_check() {
    local label="$1"
    local result="$2"   # "ok" | "warn" | "fail"
    local msg="$3"
    case "${result}" in
        ok)   log  "${label}: ${msg}" ;;
        warn) warn "${label}: ${msg}"; ((PREFLIGHT_WARNINGS++)) ;;
        fail) err  "${label}: ${msg}"; ((PREFLIGHT_ERRORS++)) ;;
    esac
}

run_preflight() {
    info "Running pre-flight checks..."

    # Architecture
    local arch
    arch=$(uname -m)
    case "${arch}" in
        aarch64|armv7l|armv6l|x86_64|amd64)
            preflight_check "Architecture" "ok" "${arch} supported" ;;
        *)
            preflight_check "Architecture" "warn" "${arch} — untested, may have issues" ;;
    esac

    # Kernel version
    local kver
    kver=$(uname -r | cut -d. -f1)
    if [[ "${kver}" -ge 5 ]]; then
        preflight_check "Kernel" "ok" "$(uname -r)"
    else
        preflight_check "Kernel" "warn" "$(uname -r) — kernel 5.x+ recommended for batman-adv"
    fi

    # Disk space — need at least 2GB free
    local free_mb
    free_mb=$(df -m / | awk 'NR==2{print $4}')
    if [[ "${free_mb}" -ge 2048 ]]; then
        preflight_check "Disk space" "ok" "${free_mb}MB free"
    elif [[ "${free_mb}" -ge 512 ]]; then
        preflight_check "Disk space" "warn" "${free_mb}MB free — 2GB+ recommended"
    else
        preflight_check "Disk space" "fail" "${free_mb}MB free — insufficient (need 512MB minimum)"
    fi

    # RAM
    local ram_mb
    ram_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
    if [[ "${ram_mb}" -ge 512 ]]; then
        preflight_check "RAM" "ok" "${ram_mb}MB"
    else
        preflight_check "RAM" "warn" "${ram_mb}MB — 512MB+ recommended. Disable monitoring module."
    fi

    # Python3
    if command -v python3 &>/dev/null; then
        preflight_check "Python3" "ok" "$(python3 --version)"
    else
        preflight_check "Python3" "fail" "python3 not found — will attempt to install"
    fi

    # git
    if command -v git &>/dev/null; then
        preflight_check "git" "ok" "$(git --version | head -1)"
    else
        preflight_check "git" "warn" "git not found — will install"
    fi

    # Network — at least one interface up
    local ifaces
    ifaces=$(ip link show up 2>/dev/null | grep -c "state UP" || echo 0)
    if [[ "${ifaces}" -gt 0 ]]; then
        preflight_check "Network" "ok" "${ifaces} interface(s) up"
    else
        preflight_check "Network" "warn" "No active network interfaces detected"
    fi

    # Wi-Fi check
    local wifi_count
    wifi_count=$(find /sys/class/net/*/wireless -maxdepth 0 2>/dev/null | wc -l)
    if [[ "${wifi_count}" -gt 0 ]]; then
        preflight_check "Wi-Fi" "ok" "${wifi_count} wireless interface(s)"
    else
        preflight_check "Wi-Fi" "warn" "No wireless interfaces — hotspot and mesh features require Wi-Fi"
    fi

    # systemd
    if command -v systemctl &>/dev/null; then
        preflight_check "systemd" "ok" "$(systemctl --version | head -1)"
    else
        preflight_check "systemd" "warn" "systemd not found — services must be managed manually"
    fi

    # Existing conflicting services
    for svc in wpa_supplicant hostapd; do
        if systemctl is-active "${svc}" &>/dev/null; then
            preflight_check "Conflict: ${svc}" "warn" "${svc} is running — Mst-PI-Station will reconfigure it"
        fi
    done

    echo ""
    if [[ "${PREFLIGHT_ERRORS}" -gt 0 ]]; then
        die "Pre-flight failed with ${PREFLIGHT_ERRORS} error(s). Resolve issues and retry."
    fi
    if [[ "${PREFLIGHT_WARNINGS}" -gt 0 ]]; then
        warn "${PREFLIGHT_WARNINGS} warning(s) — proceeding anyway"
    else
        log "All pre-flight checks passed"
    fi
}
