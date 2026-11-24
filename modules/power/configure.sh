#!/usr/bin/env bash
set -euo pipefail

POWER_MODE="${POWER_MODE:-balanced}"  # powersave | balanced | performance
DISABLE_HDMI="${DISABLE_HDMI:-0}"
DISABLE_LEDS="${DISABLE_LEDS:-0}"
DISABLE_BLUETOOTH="${DISABLE_BLUETOOTH:-0}"
DISABLE_USB="${DISABLE_USB:-0}"       # Dangerous — disables USB power (kills RNode/LTE)
CPU_MAX_FREQ="${CPU_MAX_FREQ:-}"      # e.g. 1200000 for 1.2GHz cap

log() { echo "[power/configure] $*"; }

# Load from mstpistation.yaml
if [[ -f /etc/mstpistation/mstpistation.yaml ]]; then
    POWER_MODE=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
print(cfg.get('power', {}).get('mode', 'balanced'))
" 2>/dev/null || echo "balanced")
    DISABLE_HDMI=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
print('1' if cfg.get('power', {}).get('disable_hdmi', False) else '0')
" 2>/dev/null || echo "0")
    DISABLE_LEDS=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
print('1' if cfg.get('power', {}).get('disable_leds', False) else '0')
" 2>/dev/null || echo "0")
    DISABLE_BLUETOOTH=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/mstpistation/mstpistation.yaml'))
print('1' if cfg.get('power', {}).get('disable_bluetooth', False) else '0')
" 2>/dev/null || echo "0")
fi

# Write apply script (called at boot by systemd service)
cat > /etc/mstpistation/power/apply-power-profile.sh << SCRIPT
#!/usr/bin/env bash
RESTORE="\${1:-}"
log() { echo "[power] \$*"; }

# CPU Governor
GOV="${POWER_MODE}"
[[ "\${GOV}" == "powersave" ]] && GOV="powersave"
[[ "\${GOV}" == "performance" ]] && GOV="performance"
[[ "\${GOV}" == "balanced" ]] && GOV="ondemand"

if [[ -n "\${RESTORE}" ]]; then
    GOV="ondemand"
fi

for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [[ -f "\${cpu_dir}/scaling_governor" ]] && echo "\${GOV}" > "\${cpu_dir}/scaling_governor" 2>/dev/null || true
done

$([ -n "${CPU_MAX_FREQ}" ] && cat << FREQ
for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [[ -f "\${cpu_dir}/scaling_max_freq" ]] && echo "${CPU_MAX_FREQ}" > "\${cpu_dir}/scaling_max_freq" 2>/dev/null || true
done
FREQ
)

# HDMI (Pi only)
$([ "${DISABLE_HDMI}" == "1" ] && cat << HDMI
if command -v tvservice &>/dev/null; then
    if [[ -z "\${RESTORE}" ]]; then
        tvservice -o 2>/dev/null || true
        log "HDMI disabled"
    else
        tvservice -p 2>/dev/null || true
    fi
elif [[ -f /sys/class/drm/card0/card0-HDMI-A-1/status ]]; then
    echo "off" > /sys/class/drm/card0/card0-HDMI-A-1/status 2>/dev/null || true
fi
HDMI
)

# Pi LEDs
$([ "${DISABLE_LEDS}" == "1" ] && cat << LEDS
for led in /sys/class/leds/led*/brightness; do
    [[ -f "\${led}" ]] && echo 0 > "\${led}" 2>/dev/null || true
done
for trigger in /sys/class/leds/led*/trigger; do
    [[ -f "\${trigger}" ]] && echo "none" > "\${trigger}" 2>/dev/null || true
done
log "LEDs disabled"
LEDS
)

# Bluetooth
$([ "${DISABLE_BLUETOOTH}" == "1" ] && cat << BT
if command -v rfkill &>/dev/null; then
    if [[ -z "\${RESTORE}" ]]; then
        rfkill block bluetooth 2>/dev/null || true
        log "Bluetooth blocked"
    else
        rfkill unblock bluetooth 2>/dev/null || true
    fi
fi
BT
)

log "Power profile applied: ${POWER_MODE}"
SCRIPT
chmod +x /etc/mstpistation/power/apply-power-profile.sh

systemctl enable mstpistation-power 2>/dev/null || true
systemctl restart mstpistation-power || true

log "Power mode: ${POWER_MODE}"
[[ "${DISABLE_HDMI}" == "1" ]]      && log "HDMI: disabled"
[[ "${DISABLE_LEDS}" == "1" ]]      && log "LEDs: disabled"
[[ "${DISABLE_BLUETOOTH}" == "1" ]] && log "Bluetooth: blocked"
