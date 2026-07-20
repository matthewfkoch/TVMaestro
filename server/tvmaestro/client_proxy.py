"""HTTP client for TVMaestro Android endpoint APIs."""

from __future__ import annotations

import asyncio
import logging
import shutil
from typing import Any, Optional

import httpx

from . import androidtv_remote
from .models import CecAction, Device, SessionState

logger = logging.getLogger(__name__)


def _headers(device: Device) -> dict[str, str]:
    h = {"Content-Type": "application/json"}
    if device.token:
        h["X-Auth-Token"] = device.token
    return h


def _base(device: Device) -> str:
    return f"http://{device.host}:{device.port}"


async def health(device: Device, timeout: float = 3.0) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(f"{_base(device)}/api/health", headers=_headers(device))
        resp.raise_for_status()
        return resp.json()


async def info(device: Device, timeout: float = 5.0) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(f"{_base(device)}/api/info", headers=_headers(device))
        resp.raise_for_status()
        return resp.json()


async def push_session(device: Device, session: SessionState, timeout: float = 15.0) -> dict[str, Any]:
    payload = {
        "id": session.id,
        "mode": session.mode,
        "layout": session.layout.value if hasattr(session.layout, "value") else session.layout,
        "slots": [
            {
                "url": s.url,
                "title": s.title,
                "audio": s.audio,
                "channel_id": s.channel_id,
            }
            for s in session.slots
        ],
    }
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(
            f"{_base(device)}/api/session",
            headers=_headers(device),
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, dict) and data.get("success") is False:
            raise RuntimeError(data.get("message") or "Client rejected session")
        return data


async def stop_session(device: Device, timeout: float = 10.0) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(
            f"{_base(device)}/api/session/stop",
            headers=_headers(device),
            json={},
        )
        resp.raise_for_status()
        return resp.json()


async def get_session(device: Device, timeout: float = 5.0) -> Optional[dict[str, Any]]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(f"{_base(device)}/api/session", headers=_headers(device))
        resp.raise_for_status()
        return resp.json()


async def remote_power(device: Device, *, on: bool) -> bool:
    """Wake/sleep via Android TV Remote Protocol (no ADB)."""
    if not androidtv_remote.has_certs(device.id):
        return False
    try:
        client = await androidtv_remote.remotes().get(device)
        await client.power(on=on)
        logger.info("remote %s %s ok", device.host, "WAKEUP" if on else "SLEEP")
        return True
    except androidtv_remote.RemoteNotPaired:
        logger.debug("remote power: %s not paired", device.host)
        return False
    except Exception as exc:  # noqa: BLE001
        logger.warning("remote power(%s): %s", device.host, exc)
        return False


async def cec(device: Device, action: CecAction, timeout: float = 5.0) -> dict[str, Any]:
    """Send CEC / power action.

    Volume/mute → Android client (AudioManager → CEC).

    Wake/Sleep order:
      1. Android TV Remote (paired) — no ADB
      2. adb WAKEUP/SLEEP — fallback when unpaired or remote fails
      3. Client HTTP (rarely works for power on Shield)
    """
    if action in (CecAction.power_on, CecAction.power_off):
        on = action == CecAction.power_on
        if await remote_power(device, on=on):
            return {
                "success": True,
                "action": action.value,
                "method": "androidtv_remote",
                "message": "Android TV Remote WAKEUP/SLEEP → CEC when Power Control enabled",
            }
        if await adb_power(device.host, on=on):
            return {
                "success": True,
                "action": action.value,
                "method": "adb_keyevent",
                "message": "adb WAKEUP/SLEEP → Shield CEC One Touch Play / Standby",
            }

    result: dict[str, Any]
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(
                f"{_base(device)}/api/cec",
                headers=_headers(device),
                json={"action": action.value},
            )
            resp.raise_for_status()
            result = resp.json()
    except Exception as exc:  # noqa: BLE001
        result = {"success": False, "action": action.value, "message": str(exc)}

    if (
        not result.get("success")
        and action in (CecAction.power_on, CecAction.power_off)
    ):
        result["message"] = (
            result.get("message")
            or "Wake/Sleep needs Android TV Remote pairing (Edit device → Pair) "
            "or adb on the TVMaestro host"
        )
    return result


async def adb_power(host: str, *, on: bool) -> bool:
    """Wake/sleep via adb network debugging (fallback)."""
    adb = shutil.which("adb")
    if not adb:
        logger.debug("adb not found on PATH; cannot power-fallback for %s", host)
        return False
    serial = host if ":" in host else f"{host}:5555"
    key = "KEYCODE_WAKEUP" if on else "KEYCODE_SLEEP"
    try:
        connect = await asyncio.create_subprocess_exec(
            adb,
            "connect",
            serial,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            await asyncio.wait_for(connect.wait(), timeout=5)
        except asyncio.TimeoutError:
            connect.kill()
        proc = await asyncio.create_subprocess_exec(
            adb,
            "-s",
            serial,
            "shell",
            "input",
            "keyevent",
            key,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            _, err = await asyncio.wait_for(proc.communicate(), timeout=8)
        except asyncio.TimeoutError:
            proc.kill()
            return False
        if proc.returncode != 0:
            logger.warning("adb power %s failed: %s", key, err.decode(errors="replace"))
            return False
        logger.info("adb %s %s ok", serial, key)
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("adb_power(%s): %s", host, exc)
        return False
