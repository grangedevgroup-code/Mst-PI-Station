#!/usr/bin/env bash
# Service control abstraction — handles systemd, openrc, procd
# Usage: service-ctl.sh <action> <service>

ACTION="$1"
SERVICE="$2"

[[ -f /etc/aetherium/distro.env ]] && source /etc/aetherium/distro.env

case "${INIT_SYSTEM:-systemd}" in
    systemd)
        case "${ACTION}" in
            enable)  systemctl enable "${SERVICE}" 2>/dev/null || true ;;
            disable) systemctl disable "${SERVICE}" 2>/dev/null || true ;;
            start)   systemctl start "${SERVICE}" ;;
            stop)    systemctl stop "${SERVICE}" ;;
            restart) systemctl restart "${SERVICE}" ;;
            reload)  systemctl reload-or-restart "${SERVICE}" ;;
            status)  systemctl is-active "${SERVICE}" ;;
            daemon-reload) systemctl daemon-reload ;;
        esac
        ;;
    openrc)
        case "${ACTION}" in
            enable)  rc-update add "${SERVICE}" default ;;
            disable) rc-update del "${SERVICE}" ;;
            start)   rc-service "${SERVICE}" start ;;
            stop)    rc-service "${SERVICE}" stop ;;
            restart) rc-service "${SERVICE}" restart ;;
            reload)  rc-service "${SERVICE}" reload ;;
            status)  rc-service "${SERVICE}" status ;;
        esac
        ;;
    procd)
        case "${ACTION}" in
            start)   /etc/init.d/"${SERVICE}" start ;;
            stop)    /etc/init.d/"${SERVICE}" stop ;;
            restart) /etc/init.d/"${SERVICE}" restart ;;
            enable)  /etc/init.d/"${SERVICE}" enable ;;
            disable) /etc/init.d/"${SERVICE}" disable ;;
        esac
        ;;
    *)
        echo "Unknown init system: ${INIT_SYSTEM}" >&2
        exit 1
        ;;
esac
