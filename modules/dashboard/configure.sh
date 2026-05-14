#!/usr/bin/env bash
# Dashboard configure — nothing to template, just restart
systemctl restart aetherium-dashboard 2>/dev/null || true
echo "[dashboard/configure] done"
