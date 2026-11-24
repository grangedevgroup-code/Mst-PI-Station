#!/usr/bin/env bash
# Mst-PI-Station Installer
# Usage: sudo bash install.sh [--profile relay] [--no-interactive]
set -euo pipefail

MSTPISTATION_VERSION="0.1.0"
MSTPISTATION_INSTALL_DIR="/opt/mstpistation"
MSTPISTATION_CONFIG_DIR="/etc/mstpistation"
MSTPISTATION_DATA_DIR="/var/lib/mstpistation"
MSTPISTATION_LOG_DIR="/var/log/mstpistation"
MSTPISTATION_RUN_DIR="/var/run/mstpistation"
MSTPISTATION_BIN="/usr/local/bin/mstpistation"

PROFILE="${MSTPISTATION_PROFILE:-}"
NON_INTERACTIVE="${MSTPISTATION_NON_INTERACTIVE:-0}"
REPO_URL="${MSTPISTATION_REPO:-https://github.com/mstpistation-project/mstpistation}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[→]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

banner() {
cat << 'EOF'

    ╔═══════════════════════════════════════════╗
    ║                                           ║
    ║    ██████  ███████ ████████ ██   ██       ║
    ║   ██       ██         ██    ██   ██       ║
    ║   ███████  █████      ██    ███████       ║
    ║        ██  ██         ██    ██   ██       ║
    ║   ██████   ███████    ██    ██   ██       ║
    ║                                           ║
    ║     Resilient Mesh Communications Stack   ║
    ╚═══════════════════════════════════════════╝

EOF
    echo -e "  ${BOLD}Version:${NC} ${MSTPISTATION_VERSION}"
    echo -e "  ${BOLD}Target:${NC}  $(uname -m) / $(uname -s)"
    echo ""
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|-p) PROFILE="$2"; shift 2 ;;
            --no-interactive) NON_INTERACTIVE=1; shift ;;
            --dir) MSTPISTATION_INSTALL_DIR="$2"; shift 2 ;;
            --help|-h) usage; exit 0 ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
}

usage() {
    echo "Usage: install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --profile <name>    Deploy profile immediately (relay|field-node|hotspot|mesh-hub|emergency)"
    echo "  --no-interactive    Skip interactive prompts"
    echo "  --dir <path>        Installation directory (default: /opt/mstpistation)"
    echo "  --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  sudo bash install.sh --profile relay"
    echo "  sudo bash install.sh --profile field-node --no-interactive"
}

# ── Privilege check ───────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Mst-PI-Station installer must be run as root. Try: sudo bash install.sh"
    fi
}

# ── Source sub-scripts ────────────────────────────────────────────────────────
source_installer() {
    local installer_dir
    if [[ -f "${SCRIPT_DIR}/installer/detect-distro.sh" ]]; then
        installer_dir="${SCRIPT_DIR}/installer"
    elif [[ -f "${MSTPISTATION_INSTALL_DIR}/installer/detect-distro.sh" ]]; then
        installer_dir="${MSTPISTATION_INSTALL_DIR}/installer"
    else
        die "Cannot find installer scripts. Is Mst-PI-Station installed to ${MSTPISTATION_INSTALL_DIR}?"
    fi
    # shellcheck source=/dev/null
    source "${installer_dir}/detect-distro.sh"
    source "${installer_dir}/detect-hardware.sh"
    source "${installer_dir}/preflight.sh"
}

# ── Install system dependencies ───────────────────────────────────────────────
install_deps() {
    info "Installing system dependencies..."
    local pkgs_debian=("python3" "python3-pip" "python3-venv" "python3-jinja2"
                       "python3-yaml" "git" "curl" "wget" "jq" "rsync" "iproute2"
                       "net-tools" "wireless-tools" "iw" "rfkill")
    local pkgs_fedora=("python3" "python3-pip" "python3-jinja2" "python3-pyyaml"
                       "git" "curl" "wget" "jq" "rsync" "iproute" "net-tools"
                       "wireless-tools" "iw" "rfkill")
    local pkgs_arch=("python" "python-pip" "python-jinja" "python-yaml"
                     "git" "curl" "wget" "jq" "iproute2" "net-tools"
                     "wireless_tools" "iw" "rfkill" "rsync")

    case "${DISTRO_FAMILY}" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq "${pkgs_debian[@]}" || true
            ;;
        fedora)
            dnf install -y -q "${pkgs_fedora[@]}" || true
            ;;
        arch)
            pacman -Sy --noconfirm --needed "${pkgs_arch[@]}" || true
            ;;
        openwrt)
            opkg update
            opkg install python3 python3-pip git curl wget jq iw
            ;;
        *)
            warn "Unknown distro family '${DISTRO_FAMILY}'. Attempting generic install..."
            ;;
    esac
    log "System dependencies installed"
}

# ── Set up Python virtual environment ────────────────────────────────────────
setup_venv() {
    info "Setting up Python environment..."
    python3 -m venv "${MSTPISTATION_INSTALL_DIR}/venv"
    "${MSTPISTATION_INSTALL_DIR}/venv/bin/pip" install --quiet --upgrade pip
    "${MSTPISTATION_INSTALL_DIR}/venv/bin/pip" install --quiet \
        jinja2 pyyaml click rich fastapi uvicorn[standard] \
        psutil python-daemon requests
    log "Python environment ready"
}

# ── Copy Mst-PI-Station files ──────────────────────────────────────────────────────
install_files() {
    info "Installing Mst-PI-Station to ${MSTPISTATION_INSTALL_DIR}..."
    if [[ "${SCRIPT_DIR}" != "${MSTPISTATION_INSTALL_DIR}" ]]; then
        if command -v rsync &>/dev/null; then
            rsync -a --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
                "${SCRIPT_DIR}/" "${MSTPISTATION_INSTALL_DIR}/"
        else
            # Fallback when rsync is unavailable (e.g. minimal OpenWrt images)
            mkdir -p "${MSTPISTATION_INSTALL_DIR}"
            cp -a "${SCRIPT_DIR}/." "${MSTPISTATION_INSTALL_DIR}/"
            rm -rf "${MSTPISTATION_INSTALL_DIR}/.git" 2>/dev/null || true
            find "${MSTPISTATION_INSTALL_DIR}" -name '__pycache__' -type d -prune \
                -exec rm -rf {} + 2>/dev/null || true
        fi
    fi

    # Create runtime directories
    mkdir -p "${MSTPISTATION_CONFIG_DIR}/site" \
             "${MSTPISTATION_DATA_DIR}" \
             "${MSTPISTATION_LOG_DIR}" \
             "${MSTPISTATION_RUN_DIR}"

    # Install CLI
    cat > "${MSTPISTATION_BIN}" << WRAPPER
#!/usr/bin/env bash
exec "${MSTPISTATION_INSTALL_DIR}/venv/bin/python3" "${MSTPISTATION_INSTALL_DIR}/bin/mstpistation" "\$@"
WRAPPER
    chmod +x "${MSTPISTATION_BIN}"

    # Set permissions
    chmod +x "${MSTPISTATION_INSTALL_DIR}/bin/mstpistation"
    chmod +x "${MSTPISTATION_INSTALL_DIR}/installer/"*.sh
    find "${MSTPISTATION_INSTALL_DIR}/modules" -name "*.sh" -exec chmod +x {} \;

    log "Files installed"
}

# ── Install systemd services ──────────────────────────────────────────────────
install_systemd() {
    if ! command -v systemctl &>/dev/null; then
        warn "systemd not found — skipping service installation"
        return
    fi
    info "Installing systemd services..."
    install -m644 "${MSTPISTATION_INSTALL_DIR}/systemd/mstpistation-agent.service" \
        /etc/systemd/system/
    install -m644 "${MSTPISTATION_INSTALL_DIR}/systemd/mstpistation-watchdog.service" \
        /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable mstpistation-agent.service
    log "Systemd services installed"
}

# ── Profile selection ─────────────────────────────────────────────────────────
suggest_profile() {
    # Suggest profile based on detected hardware
    local has_rnode=0 has_lte=0 wifi_count=0 eth_count=0 ram_mb=0

    [[ "${#HW_RNODE_DEVICES[@]}" -gt 0 ]] && has_rnode=1
    [[ "${#HW_LTE_DEVICES[@]}" -gt 0 ]]   && has_lte=1
    wifi_count="${#HW_WIFI_INTERFACES[@]}"
    eth_count="${#HW_ETH_INTERFACES[@]}"
    ram_mb="${HW_RAM_MB:-0}"

    if [[ "${has_lte}" == "1" ]] && [[ "${has_rnode}" == "1" ]]; then
        echo "lte-gateway"
    elif [[ "${has_lte}" == "1" ]]; then
        echo "lte-gateway"
    elif [[ "${has_rnode}" == "1" ]] && [[ "${wifi_count}" -ge 1 ]]; then
        echo "relay"
    elif [[ "${wifi_count}" -ge 2 ]] && [[ "${eth_count}" -ge 1 ]]; then
        echo "mesh-hub"
    elif [[ "${wifi_count}" -ge 1 ]] && [[ "${eth_count}" -ge 1 ]]; then
        echo "relay"
    elif [[ "${wifi_count}" -ge 1 ]] && [[ "${ram_mb}" -lt 512 ]] && [[ "${ram_mb}" -gt 0 ]]; then
        echo "field-node"
    elif [[ "${wifi_count}" -ge 1 ]]; then
        echo "relay"
    else
        echo "relay"
    fi
}

select_profile() {
    if [[ -n "${PROFILE}" ]]; then
        return
    fi

    local suggested
    suggested=$(suggest_profile)

    if [[ "${NON_INTERACTIVE}" == "1" ]]; then
        PROFILE="${suggested}"
        info "Auto-selected profile: ${PROFILE} (based on detected hardware)"
        return
    fi

    echo ""
    echo -e "${BOLD}Select a deployment profile:${NC}"
    echo ""
    echo -e "  ${GREEN}Recommended for this hardware: ${suggested}${NC}"
    echo ""
    echo "  1) relay          - Persistent mesh relay node"
    echo "  2) field-node     - Portable field communications node"
    echo "  3) hotspot        - Wi-Fi hotspot with local services"
    echo "  4) mesh-hub       - Community mesh hub with full services"
    echo "  5) lte-gateway    - LTE/4G uplink gateway for mesh network"
    echo "  6) emergency      - Minimal emergency communications node"
    echo "  7) solar-relay    - Low-power solar relay"
    echo "  8) local-services - Local file sharing and offline content server"
    echo "  9) skip           - Install only, deploy later with: mstpistation deploy <profile>"
    echo ""
    read -rp "Enter selection [1-9] or press Enter to accept recommendation: " sel
    if [[ -z "${sel}" ]]; then
        PROFILE="${suggested}"
        info "Using recommended profile: ${PROFILE}"
        return
    fi
    case "${sel}" in
        1) PROFILE="relay" ;;
        2) PROFILE="field-node" ;;
        3) PROFILE="hotspot" ;;
        4) PROFILE="mesh-hub" ;;
        5) PROFILE="lte-gateway" ;;
        6) PROFILE="emergency" ;;
        7) PROFILE="solar-relay" ;;
        8) PROFILE="local-services" ;;
        9) PROFILE="" ;;
        *) PROFILE="${suggested}"; warn "Invalid selection, using recommendation: ${suggested}" ;;
    esac
}

# ── Write initial config ──────────────────────────────────────────────────────
write_initial_config() {
    local cfg="${MSTPISTATION_CONFIG_DIR}/mstpistation.yaml"
    if [[ -f "${cfg}" ]]; then
        warn "Config already exists at ${cfg} — not overwriting"
        return
    fi
    info "Writing initial configuration..."

    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "mstpistation-node")

    cp "${MSTPISTATION_INSTALL_DIR}/mstpistation.yaml.example" "${cfg}"
    sed -i "s/mstpistation-node/${hostname}/g" "${cfg}"

    log "Configuration written to ${cfg}"
}

# ── Print summary ─────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Mst-PI-Station Install Complete!        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Install dir:${NC}  ${MSTPISTATION_INSTALL_DIR}"
    echo -e "  ${BOLD}Config dir:${NC}   ${MSTPISTATION_CONFIG_DIR}"
    echo -e "  ${BOLD}Hardware:${NC}     ${HW_MODEL:-unknown}"
    echo -e "  ${BOLD}Distro:${NC}       ${DISTRO_NAME:-unknown}"
    echo -e "  ${BOLD}Arch:${NC}         $(uname -m)"
    if [[ -n "${PROFILE}" ]]; then
        echo -e "  ${BOLD}Profile:${NC}      ${PROFILE}"
    fi
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    if [[ -z "${PROFILE}" ]]; then
        echo "    mstpistation deploy relay"
        echo "    mstpistation deploy field-node"
        echo "    mstpistation deploy hotspot"
    fi
    echo "    mstpistation status"
    echo "    mstpistation module list"
    echo "    nano /etc/mstpistation/mstpistation.yaml"
    echo ""
    echo -e "  ${BOLD}Dashboard:${NC}  http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):8080"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    banner
    check_root
    source_installer
    run_preflight
    detect_distro
    detect_hardware
    install_deps
    install_files
    setup_venv
    install_systemd
    write_initial_config
    select_profile

    if [[ -n "${PROFILE}" ]]; then
        info "Deploying profile: ${PROFILE}"
        "${MSTPISTATION_BIN}" deploy "${PROFILE}" || warn "Deploy had errors — check: mstpistation status"
    fi

    # On procd/OpenWrt: convert systemd .service files to init.d scripts
    bash "${SCRIPT_DIR}/installer/service-compat.sh" 2>/dev/null || true

    systemctl start mstpistation-agent.service 2>/dev/null || true
    print_summary
}

main "$@"
