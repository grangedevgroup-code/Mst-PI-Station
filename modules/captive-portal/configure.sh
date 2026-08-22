#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-Aetherium Node}"
HOTSPOT_SSID="${HOTSPOT_SSID:-Aetherium}"
DASHBOARD_URL="${DASHBOARD_URL:-http://aetherium.local:8080}"
PORTAL_CONTACT="${PORTAL_CONTACT:-}"

log() { echo "[captive-portal/configure] $*"; }

# Read node info for portal page
APRS_CALLSIGN="N0CALL"
if [[ -f /etc/aetherium/aetherium.yaml ]]; then
    APRS_CALLSIGN=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('/etc/aetherium/aetherium.yaml'))
print(cfg.get('aprs', {}).get('callsign', 'N0CALL'))
" 2>/dev/null || echo "N0CALL")
fi

GPS_TEXT=""
if [[ -f /var/lib/aetherium/location.json ]]; then
    GPS_TEXT=$(python3 -c "
import json
d = json.load(open('/var/lib/aetherium/location.json'))
lat, lon = d.get('lat', 0), d.get('lon', 0)
print(f'{lat:.4f}°, {lon:.4f}°')
" 2>/dev/null || echo "")
fi

# Build portal HTML
cat > /var/www/aetherium-portal/index.html << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Aetherium — ${NODE_NAME}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #0d1117; color: #c9d1d9; min-height: 100vh;
         display: flex; align-items: center; justify-content: center; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 12px;
          max-width: 480px; width: 90%; padding: 2rem; text-align: center; }
  .logo { font-size: 3rem; margin-bottom: 0.5rem; }
  h1 { font-size: 1.5rem; color: #58a6ff; margin-bottom: 0.25rem; }
  .subtitle { color: #8b949e; font-size: 0.9rem; margin-bottom: 1.5rem; }
  .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; margin-bottom: 1.5rem; }
  .info-box { background: #0d1117; border: 1px solid #21262d; border-radius: 8px; padding: 0.75rem; }
  .info-label { font-size: 0.7rem; color: #8b949e; text-transform: uppercase; letter-spacing: 0.05em; }
  .info-value { font-size: 1rem; color: #e6edf3; font-weight: 600; margin-top: 0.2rem; }
  .btn { display: inline-block; background: #238636; color: #fff; text-decoration: none;
         padding: 0.75rem 1.5rem; border-radius: 6px; font-size: 0.95rem;
         font-weight: 600; transition: background 0.2s; }
  .btn:hover { background: #2ea043; }
  .footer { margin-top: 1.5rem; font-size: 0.75rem; color: #6e7681; }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
         background: #3fb950; margin-right: 0.4rem; }
</style>
</head>
<body>
<div class="card">
  <div class="logo">Æ</div>
  <h1>${NODE_NAME}</h1>
  <p class="subtitle">Aetherium Mesh Node — ${HOTSPOT_SSID}</p>

  <div class="info-grid">
    <div class="info-box">
      <div class="info-label">Network</div>
      <div class="info-value">${HOTSPOT_SSID}</div>
    </div>
    <div class="info-box">
      <div class="info-label">Status</div>
      <div class="info-value"><span class="dot"></span>Online</div>
    </div>
    $([ -n "${APRS_CALLSIGN}" ] && [ "${APRS_CALLSIGN}" != "N0CALL" ] && cat << GRID
    <div class="info-box">
      <div class="info-label">Callsign</div>
      <div class="info-value">${APRS_CALLSIGN}</div>
    </div>
GRID
)
    $([ -n "${GPS_TEXT}" ] && cat << GRID
    <div class="info-box">
      <div class="info-label">Location</div>
      <div class="info-value" style="font-size:0.8rem">${GPS_TEXT}</div>
    </div>
GRID
)
  </div>

  <a href="${DASHBOARD_URL}" class="btn">Open Dashboard</a>

  $([ -n "${PORTAL_CONTACT}" ] && echo "<p class=\"footer\">Contact: ${PORTAL_CONTACT}</p>")
  <p class="footer">Aetherium Mesh — open-source off-grid communications</p>
</div>
</body>
</html>
HTML

# Validate and reload nginx
nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || systemctl restart nginx || true

log "Captive portal live at http://aetherium.local"
