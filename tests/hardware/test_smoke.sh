#!/usr/bin/env bash
# Smoke tests — run on actual hardware after install
# Usage: sudo bash tests/hardware/test_smoke.sh

PASS=0; FAIL=0

check() {
    local name="$1"; local cmd="$2"
    if eval "${cmd}" &>/dev/null; then
        echo "  PASS: ${name}"
        ((PASS++))
    else
        echo "  FAIL: ${name}"
        ((FAIL++))
    fi
}

echo "=== Aetherium Smoke Tests ==="
echo ""
echo "--- CLI ---"
check "aetherium binary exists" "command -v aetherium"
check "aetherium --version" "aetherium --version"

echo ""
echo "--- Python stack ---"
check "RNS importable" "/opt/aetherium/venv/bin/python3 -c 'import RNS'"
check "LXMF importable" "/opt/aetherium/venv/bin/python3 -c 'import LXMF'"
check "jinja2 importable" "/opt/aetherium/venv/bin/python3 -c 'import jinja2'"
check "fastapi importable" "/opt/aetherium/venv/bin/python3 -c 'import fastapi'"

echo ""
echo "--- Configs ---"
check "/etc/aetherium/aetherium.yaml exists" "test -f /etc/aetherium/aetherium.yaml"
check "/etc/aetherium/hardware.yaml exists" "test -f /etc/aetherium/hardware.yaml"

echo ""
echo "--- Services ---"
check "systemd available" "command -v systemctl"
check "aetherium-agent service file exists" "test -f /etc/systemd/system/aetherium-agent.service"

echo ""
echo "--- Network ---"
check "ip command available" "command -v ip"
check "iw command available" "command -v iw"

echo ""
echo "--- Kernel modules ---"
check "batman-adv module loadable" "modprobe batman-adv && modinfo batman-adv"

echo ""
echo "==========================="
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
