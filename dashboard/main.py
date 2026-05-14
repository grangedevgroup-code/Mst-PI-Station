"""
Aetherium Dashboard — FastAPI web UI
Served on port 8080, accessible at http://aetherium.local:8080
"""

import os
import sys
import json
import time
import subprocess
import asyncio
from pathlib import Path
from typing import Dict, Any, Optional

from fastapi import FastAPI, Request, HTTPException, Form, WebSocket
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import uvicorn
import yaml
import psutil

AETHERIUM_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(AETHERIUM_DIR))

from core.config import Config
from core.hardware import Hardware
from core.modules import ModuleManager

app = FastAPI(title="Aetherium Dashboard", version="0.1.0", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=str(Path(__file__).parent / "static")), name="static")
templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))

STATUS_FILE = Path("/var/run/aetherium/status.json")
CONFIG_FILE = Path("/etc/aetherium/aetherium.yaml")


def get_status() -> Dict[str, Any]:
    if STATUS_FILE.exists():
        try:
            with open(STATUS_FILE) as f:
                return json.load(f)
        except Exception:
            pass
    return {"node": "aetherium", "profile": "unknown", "healthy": False,
            "services": {}, "interfaces": [], "system": {}}


def get_config() -> Config:
    return Config()


def get_hardware() -> Hardware:
    return Hardware()


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    status = get_status()
    cfg = get_config()
    hw = get_hardware()

    # Live system stats
    cpu_percent = psutil.cpu_percent(interval=0.1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    cpu_temp = _cpu_temp()
    uptime = _uptime()

    mm = ModuleManager(AETHERIUM_DIR, cfg, hw)
    modules = mm.list_modules()
    active_modules = [m for m in modules if m["status"] == "active"]

    return templates.TemplateResponse("index.html", {
        "request": request,
        "node_name": cfg.get("node.name", "aetherium-node"),
        "profile": cfg.get("node.profile", "unconfigured"),
        "status": status,
        "cpu_percent": cpu_percent,
        "mem_percent": mem.percent,
        "mem_used_mb": mem.used // 1024 // 1024,
        "mem_total_mb": mem.total // 1024 // 1024,
        "disk_percent": disk.percent,
        "disk_used_gb": disk.used // 1024 // 1024 // 1024,
        "disk_total_gb": disk.total // 1024 // 1024 // 1024,
        "cpu_temp": cpu_temp,
        "uptime": uptime,
        "active_modules": active_modules,
        "modules": modules,
        "hw": hw,
        "healthy": status.get("healthy", False),
    })


@app.get("/network", response_class=HTMLResponse)
async def network(request: Request):
    status = get_status()
    interfaces = status.get("interfaces", [])

    # Enrich with iw info
    for iface in interfaces:
        name = iface["name"]
        iface["signal"] = _iface_signal(name)
        iface["mode"] = _iface_mode(name)
        iface["ssid"] = _iface_ssid(name)

    batman_peers = _batman_peers()
    mesh_stats = status.get("mesh", {})

    return templates.TemplateResponse("network.html", {
        "request": request,
        "node_name": get_config().get("node.name", "aetherium-node"),
        "interfaces": interfaces,
        "batman_peers": batman_peers,
        "mesh_stats": mesh_stats,
    })


@app.get("/services", response_class=HTMLResponse)
async def services(request: Request):
    cfg = get_config()
    hw = get_hardware()
    mm = ModuleManager(AETHERIUM_DIR, cfg, hw)
    modules = mm.list_modules()

    return templates.TemplateResponse("services.html", {
        "request": request,
        "node_name": cfg.get("node.name", "aetherium-node"),
        "modules": modules,
    })


@app.post("/services/{name}/enable")
async def service_enable(name: str, request: Request):
    if os.geteuid() == 0:
        cfg = get_config()
        hw = get_hardware()
        mm = ModuleManager(AETHERIUM_DIR, cfg, hw)
        success, msg = mm.enable(name)
        return JSONResponse({"success": success, "message": msg})
    return JSONResponse({"success": False, "message": "Dashboard not running as root"}, status_code=403)


@app.post("/services/{name}/disable")
async def service_disable(name: str, request: Request):
    if os.geteuid() == 0:
        cfg = get_config()
        hw = get_hardware()
        mm = ModuleManager(AETHERIUM_DIR, cfg, hw)
        success, msg = mm.disable(name)
        return JSONResponse({"success": success, "message": msg})
    return JSONResponse({"success": False, "message": "Dashboard not running as root"}, status_code=403)


@app.get("/config", response_class=HTMLResponse)
async def config_page(request: Request):
    cfg_text = ""
    if CONFIG_FILE.exists():
        cfg_text = CONFIG_FILE.read_text()
    return templates.TemplateResponse("config.html", {
        "request": request,
        "node_name": get_config().get("node.name", "aetherium-node"),
        "config_text": cfg_text,
        "config_file": str(CONFIG_FILE),
    })


@app.post("/config")
async def config_save(request: Request, config_text: str = Form(...)):
    if os.geteuid() == 0:
        try:
            # Validate YAML
            yaml.safe_load(config_text)
            CONFIG_FILE.write_text(config_text)
            return JSONResponse({"success": True, "message": "Configuration saved"})
        except yaml.YAMLError as e:
            return JSONResponse({"success": False, "message": f"Invalid YAML: {e}"}, status_code=400)
    return JSONResponse({"success": False, "message": "Read-only: dashboard not running as root"}, status_code=403)


@app.get("/api/status")
async def api_status():
    return get_status()


@app.get("/api/metrics")
async def api_metrics():
    cpu = psutil.cpu_percent(interval=0.1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    return {
        "cpu_percent": cpu,
        "cpu_temp": _cpu_temp(),
        "mem_percent": mem.percent,
        "mem_used_mb": mem.used // 1024 // 1024,
        "mem_total_mb": mem.total // 1024 // 1024,
        "disk_percent": disk.percent,
        "uptime_seconds": _uptime_secs(),
        "timestamp": time.time(),
    }


@app.get("/api/peers")
async def api_peers():
    peers_file = Path("/var/lib/aetherium/peers.json")
    if peers_file.exists():
        return json.loads(peers_file.read_text())
    return []


@app.websocket("/ws/metrics")
async def ws_metrics(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            metrics = {
                "cpu": psutil.cpu_percent(interval=0.1),
                "mem": psutil.virtual_memory().percent,
                "temp": _cpu_temp(),
                "uptime": _uptime(),
                "timestamp": time.time(),
            }
            await websocket.send_json(metrics)
            await asyncio.sleep(3)
    except Exception:
        pass


# ── Helpers ───────────────────────────────────────────────────────────────────

def _cpu_temp() -> Optional[float]:
    for path in ["/sys/class/thermal/thermal_zone0/temp",
                 "/sys/class/hwmon/hwmon0/temp1_input"]:
        try:
            raw = int(Path(path).read_text().strip())
            return round(raw / 1000, 1)
        except Exception:
            pass
    return None


def _uptime() -> str:
    secs = _uptime_secs()
    h, rem = divmod(secs, 3600)
    m = rem // 60
    return f"{h}h {m}m"


def _uptime_secs() -> int:
    try:
        with open("/proc/uptime") as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return 0


def _iface_signal(iface: str) -> str:
    try:
        r = subprocess.run(["iw", "dev", iface, "link"],
                           capture_output=True, text=True, timeout=3)
        for line in r.stdout.split("\n"):
            if "signal" in line.lower():
                return line.strip()
    except Exception:
        pass
    return ""


def _iface_mode(iface: str) -> str:
    try:
        r = subprocess.run(["iw", "dev", iface, "info"],
                           capture_output=True, text=True, timeout=3)
        for line in r.stdout.split("\n"):
            if "type" in line:
                return line.strip().replace("type ", "")
    except Exception:
        pass
    return ""


def _iface_ssid(iface: str) -> str:
    try:
        r = subprocess.run(["iw", "dev", iface, "info"],
                           capture_output=True, text=True, timeout=3)
        for line in r.stdout.split("\n"):
            if "ssid" in line.lower():
                return line.strip().replace("ssid ", "")
    except Exception:
        pass
    return ""


def _batman_peers() -> list:
    try:
        r = subprocess.run(["batctl", "n", "-H"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            peers = []
            for line in r.stdout.strip().split("\n"):
                parts = line.split()
                if len(parts) >= 2:
                    peers.append({"mac": parts[0], "iface": parts[1] if len(parts) > 1 else ""})
            return peers
    except Exception:
        pass
    return []


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="warning")
