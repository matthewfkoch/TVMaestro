"""TVMaestro FastAPI application."""

from __future__ import annotations

import asyncio
import logging
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import __version__, client_proxy
from . import androidtv_remote
from .apituner import ApiTunerClient, ApiTunerError
from .config import ConfigStore
from .devices import DeviceRegistry
from .guide import GuideStore
from .models import (
    CecByHostRequest,
    CecRequest,
    ConfigUpdate,
    DeviceCreate,
    DeviceUpdate,
    PairFinishRequest,
    SessionCreate,
    YoutubeTuneRequest,
)
from .secrets import drop_unchanged_secrets, public_config, public_device
from .sessions import SessionManager

logging.basicConfig(
    level=os.environ.get("TVMAESTRO_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("tvmaestro")

WEB_DIR = Path(__file__).parent / "web"


@asynccontextmanager
async def lifespan(app: FastAPI):
    store = ConfigStore()
    guide = GuideStore(store)
    devices = DeviceRegistry()
    apituner = ApiTunerClient(store)
    sessions = SessionManager(devices, guide, apituner)

    app.state.store = store
    app.state.guide = guide
    app.state.devices = devices
    app.state.sessions = sessions
    app.state.apituner = apituner

    await guide.start()
    await devices.start()
    logger.info("TVMaestro %s ready", __version__)
    yield
    await devices.stop()
    await guide.stop()


app = FastAPI(title="TVMaestro", version=__version__, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _guide() -> GuideStore:
    return app.state.guide


def _devices() -> DeviceRegistry:
    return app.state.devices


def _sessions() -> SessionManager:
    return app.state.sessions


def _store() -> ConfigStore:
    return app.state.store


def _apituner() -> ApiTunerClient:
    return app.state.apituner


@app.get("/api/status")
async def status():
    guide = _guide()
    store = _store()
    devices = _devices().list()
    return {
        "version": __version__,
        "channels": len(guide.channels),
        "programmes": len(guide.programmes),
        "channels_updated_at": guide.channels_updated_at,
        "epg_updated_at": guide.epg_updated_at,
        "last_error": guide.last_error,
        "devices_online": sum(1 for d in devices if d.online),
        "devices_total": len(devices),
        "apituner_configured": bool(store.config.apituner_base_url.strip()),
        "now": time.time(),
    }


@app.get("/api/config")
async def get_config():
    return public_config(_store().config.model_dump())


@app.put("/api/config")
async def put_config(body: ConfigUpdate):
    updates = drop_unchanged_secrets(body.model_dump(exclude_unset=True))
    cfg = _store().update(**updates)
    return public_config(cfg.model_dump())


@app.post("/api/refresh")
async def refresh(target: str = Query("all", pattern="^(all|channels|epg)$")):
    guide = _guide()
    try:
        if target in ("all", "channels"):
            await guide.refresh_channels()
        if target in ("all", "epg"):
            await guide.refresh_epg()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"Refresh failed: {exc}") from exc
    return {"ok": True, "channels": len(guide.channels), "programmes": len(guide.programmes)}


@app.get("/api/channels")
async def channels():
    return _guide().channels


@app.get("/api/epg")
async def epg(
    from_ts: Optional[int] = Query(None, alias="from"),
    to_ts: Optional[int] = Query(None, alias="to"),
    channel: Optional[str] = None,
):
    ids = {channel} if channel else None
    return _guide().epg(from_ts=from_ts, to_ts=to_ts, channel_ids=ids)


@app.get("/api/devices")
async def list_devices():
    return [public_device(d.model_dump()) for d in _devices().list()]


@app.post("/api/devices")
async def create_device(body: DeviceCreate):
    device = await _devices().add(body)
    await _devices().poll_one(device.id)
    device = _devices().get(device.id)
    return public_device(device.model_dump()) if device else device


@app.get("/api/devices/{device_id}")
async def get_device(device_id: str):
    device = _devices().get(device_id)
    if not device:
        raise HTTPException(404, "Device not found")
    return public_device(device.model_dump())


@app.patch("/api/devices/{device_id}")
async def patch_device(device_id: str, body: DeviceUpdate):
    updates = drop_unchanged_secrets(
        body.model_dump(exclude_unset=True),
        keys=("token",),
    )
    device = await _devices().update(device_id, DeviceUpdate(**updates))
    if not device:
        raise HTTPException(404, "Device not found")
    await _devices().poll_one(device_id)
    device = _devices().get(device_id)
    return public_device(device.model_dump()) if device else device


@app.delete("/api/devices/{device_id}")
async def delete_device(device_id: str):
    if not _devices().get(device_id):
        raise HTTPException(404, "Device not found")
    await _sessions().stop_device(device_id)
    await _devices().delete(device_id)
    await androidtv_remote.remotes().drop(device_id)
    return {"ok": True}


@app.get("/api/devices/{device_id}/status")
async def device_status(device_id: str):
    device = await _devices().poll_one(device_id)
    if not device:
        raise HTTPException(404, "Device not found")
    session = _sessions().for_device(device_id)
    remote = None
    if device.online:
        try:
            remote = await client_proxy.get_session(device)
        except Exception as exc:  # noqa: BLE001
            remote = {"error": str(exc)}
    return {
        "device": public_device(device.model_dump()),
        "session": session,
        "remote_session": remote,
    }


@app.post("/api/devices/{device_id}/cec")
async def device_cec(device_id: str, body: CecRequest):
    device = _devices().get(device_id)
    if not device:
        raise HTTPException(404, "Device not found")
    try:
        result = await client_proxy.cec(device, body.action)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"CEC failed: {exc}") from exc
    return result


@app.post("/api/cec/by-host")
async def cec_by_host(body: CecByHostRequest):
    """Wake/sleep (or volume) a registered device by LAN IP — used by the Android settings test."""
    host = body.host.strip()
    device = next((d for d in _devices().list() if d.host == host), None)
    if not device:
        raise HTTPException(404, f"No registered device with host {host}")
    try:
        return await client_proxy.cec(device, body.action)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"CEC failed: {exc}") from exc


@app.get("/api/devices/{device_id}/pair/status")
async def pair_status(device_id: str):
    device = _devices().get(device_id)
    if not device:
        raise HTTPException(404, "Device not found")
    has = androidtv_remote.has_certs(device_id)
    paired = False
    if has:
        try:
            client = await androidtv_remote.remotes().get(device)
            paired = await asyncio.wait_for(client.is_paired(), timeout=6)
        except Exception:  # noqa: BLE001
            paired = has
    return {
        "requires_pairing": True,
        "paired": paired,
        "has_certs": has,
        "method": "androidtv_remote",
    }


@app.post("/api/devices/{device_id}/pair/start")
async def pair_start(device_id: str):
    device = _devices().get(device_id)
    if not device:
        raise HTTPException(404, "Device not found")
    try:
        client = await androidtv_remote.remotes().get(device)
        await client.start_pairing()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"Pairing start failed: {exc}") from exc
    return {"ok": True, "message": "Enter the PIN shown on the TV"}


@app.post("/api/devices/{device_id}/pair/finish")
async def pair_finish(device_id: str, body: PairFinishRequest):
    device = _devices().get(device_id)
    if not device:
        raise HTTPException(404, "Device not found")
    pin = (body.pin or "").strip()
    if not pin:
        raise HTTPException(400, "PIN is required")
    try:
        client = await androidtv_remote.remotes().get(device)
        await client.finish_pairing(pin)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"Pairing finish failed: {exc}") from exc
    # Refresh capability flags on next poll
    await _devices().poll_one(device_id)
    return {"ok": True, "paired": True}


@app.get("/api/sessions")
async def list_sessions():
    return _sessions().list()


@app.post("/api/sessions")
async def create_session(body: SessionCreate):
    try:
        session = await _sessions().create(body)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except ApiTunerError as exc:
        raise HTTPException(502, str(exc)) from exc
    if session.status == "error":
        raise HTTPException(502, session.error or "Failed to start session on device")
    return session


@app.get("/api/sessions/{session_id}")
async def get_session(session_id: str):
    session = _sessions().get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    return session


@app.delete("/api/sessions/{session_id}")
async def delete_session(session_id: str):
    session = await _sessions().stop(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    return session


@app.post("/api/sessions/{session_id}/stop")
async def stop_session(session_id: str):
    session = await _sessions().stop(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    return session


@app.post("/api/youtube/resolve")
async def youtube_resolve(body: YoutubeTuneRequest):
    try:
        slot = await _apituner().resolve_youtube_slot(body.youtube_url, title=body.title)
    except ApiTunerError as exc:
        raise HTTPException(502, str(exc)) from exc
    return slot


@app.get("/api/apituner/status")
async def apituner_status():
    try:
        return await _apituner().status()
    except Exception as exc:  # noqa: BLE001
        return {"enabled": _apituner().enabled, "error": str(exc)}


# Static web UI (built assets). In dev, Vite proxies /api.
if WEB_DIR.is_dir():
    assets = WEB_DIR / "assets"
    if assets.is_dir():
        app.mount("/assets", StaticFiles(directory=assets), name="assets")

    @app.get("/")
    async def index():
        index_path = WEB_DIR / "index.html"
        if index_path.exists():
            return FileResponse(index_path)
        raise HTTPException(404, "Web UI not built")

    @app.get("/{path:path}")
    async def spa_fallback(path: str):
        if path.startswith("api/"):
            raise HTTPException(404)
        candidate = _safe_web_path(path)
        if candidate is not None and candidate.is_file():
            return FileResponse(candidate)
        index_path = WEB_DIR / "index.html"
        if index_path.exists():
            return FileResponse(index_path)
        raise HTTPException(404)


def _safe_web_path(path: str) -> Path | None:
    """Resolve a SPA asset path, rejecting traversal outside WEB_DIR."""
    if not path or path.startswith("/") or ".." in Path(path).parts:
        return None
    try:
        web_root = WEB_DIR.resolve()
        candidate = (web_root / path).resolve()
        candidate.relative_to(web_root)
    except (OSError, ValueError):
        return None
    return candidate
