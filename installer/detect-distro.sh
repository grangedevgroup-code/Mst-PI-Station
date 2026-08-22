#!/usr/bin/env bash
# Distro and package manager detection
# Sourced by install.sh — sets DISTRO_FAMILY, DISTRO_NAME, DISTRO_VERSION, PKG_MGR

DISTRO_FAMILY=""
DISTRO_NAME=""
DISTRO_VERSION=""
PKG_MGR=""
INIT_SYSTEM=""

detect_distro() {
    # Init system
    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service &>/dev/null; then
        INIT_SYSTEM="openrc"
    elif [[ -f /etc/openwrt_release ]]; then
        INIT_SYSTEM="procd"
    else
        INIT_SYSTEM="unknown"
    fi

    # Distro detection
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO_NAME="${NAME:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        case "${ID:-}" in
            debian|ubuntu|linuxmint|pop|elementary|kali|parrot|raspbian)
                DISTRO_FAMILY="debian"
                PKG_MGR="apt-get"
                ;;
            fedora)
                DISTRO_FAMILY="fedora"
                PKG_MGR="dnf"
                ;;
            centos|rhel|rocky|almalinux)
                DISTRO_FAMILY="fedora"
                PKG_MGR="dnf"
                ;;
            arch|manjaro|endeavouros)
                DISTRO_FAMILY="arch"
                PKG_MGR="pacman"
                ;;
            opensuse*|sles)
                DISTRO_FAMILY="suse"
                PKG_MGR="zypper"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                PKG_MGR="apk"
                ;;
            *)
                # Fallback: check ID_LIKE
                case "${ID_LIKE:-}" in
                    *debian*|*ubuntu*) DISTRO_FAMILY="debian"; PKG_MGR="apt-get" ;;
                    *fedora*|*rhel*)   DISTRO_FAMILY="fedora"; PKG_MGR="dnf" ;;
                    *arch*)            DISTRO_FAMILY="arch";   PKG_MGR="pacman" ;;
                    *)                 DISTRO_FAMILY="unknown" ;;
                esac
                ;;
        esac
    elif [[ -f /etc/openwrt_release ]]; then
        # shellcheck source=/dev/null
        source /etc/openwrt_release
        DISTRO_FAMILY="openwrt"
        DISTRO_NAME="OpenWrt"
        DISTRO_VERSION="${DISTRIB_RELEASE:-unknown}"
        PKG_MGR="opkg"
        INIT_SYSTEM="procd"
        # OpenWrt notes:
        #   - Docker is not available; container modules (Matrix, Gitea, Syncthing, Mumble,
        #     Monitoring) will be skipped automatically
        #   - systemd .service files are converted to procd init.d scripts by service-compat.sh
        #   - Python venv requires python3 from opkg; install may be slow
    elif [[ -f /etc/debian_version ]]; then
        DISTRO_FAMILY="debian"
        DISTRO_NAME="Debian"
        DISTRO_VERSION=$(cat /etc/debian_version)
        PKG_MGR="apt-get"
    else
        DISTRO_FAMILY="unknown"
        DISTRO_NAME="Unknown"
        warn "Could not detect Linux distribution. Some features may not work."
    fi

    # Write for later use
    mkdir -p /etc/aetherium
    cat > /etc/aetherium/distro.env << EOF
DISTRO_FAMILY="${DISTRO_FAMILY}"
DISTRO_NAME="${DISTRO_NAME}"
DISTRO_VERSION="${DISTRO_VERSION}"
PKG_MGR="${PKG_MGR}"
INIT_SYSTEM="${INIT_SYSTEM}"
EOF

    log "Detected: ${DISTRO_NAME} ${DISTRO_VERSION} (${DISTRO_FAMILY}) / ${INIT_SYSTEM}"
}

# Package install abstraction used by modules
pkg_install() {
    # shellcheck source=/dev/null
    [[ -f /etc/aetherium/distro.env ]] && source /etc/aetherium/distro.env

    case "${DISTRO_FAMILY}" in
        debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
            ;;
        fedora)
            dnf install -y -q "$@"
            ;;
        arch)
            pacman -S --noconfirm --needed "$@"
            ;;
        suse)
            zypper install -y "$@"
            ;;
        alpine)
            apk add --quiet "$@"
            ;;
        openwrt)
            opkg install "$@"
            ;;
        *)
            warn "Cannot auto-install packages on ${DISTRO_FAMILY}. Please install manually: $*"
            return 1
            ;;
    esac
}

pkg_installed() {
    local pkg="$1"
    case "${DISTRO_FAMILY}" in
        debian)  dpkg -l "${pkg}" 2>/dev/null | grep -q "^ii" ;;
        fedora)  rpm -q "${pkg}" &>/dev/null ;;
        arch)    pacman -Qi "${pkg}" &>/dev/null ;;
        alpine)  apk info -e "${pkg}" &>/dev/null ;;
        *)       command -v "${pkg}" &>/dev/null ;;
    esac
}

svc_enable()  { "${AETHERIUM_INSTALL_DIR:-/opt/aetherium}/installer/service-ctl.sh" enable "$@"; }
svc_start()   { "${AETHERIUM_INSTALL_DIR:-/opt/aetherium}/installer/service-ctl.sh" start "$@"; }
svc_restart() { "${AETHERIUM_INSTALL_DIR:-/opt/aetherium}/installer/service-ctl.sh" restart "$@"; }
svc_stop()    { "${AETHERIUM_INSTALL_DIR:-/opt/aetherium}/installer/service-ctl.sh" stop "$@"; }
svc_status()  { "${AETHERIUM_INSTALL_DIR:-/opt/aetherium}/installer/service-ctl.sh" status "$@"; }
