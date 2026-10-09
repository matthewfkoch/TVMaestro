"""HTTP client for TVMaestro Android and Apple TV endpoint APIs."""

from __future__ import annotations

import asyncio
import json
import logging
import re
import shutil
import time
from typing import Any, Optional

import httpx

from . import androidtv_remote, appletv_remote
from .models import CecAction, Device, SessionState

logger = logging.getLogger(__name__)

_HTML_TITLE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)


def _headers(device: Device) -> dict[str, str]:
    h = {"Content-Type": "application/json"}
    if device.token:
        h["X-Auth-Token"] = device.token
    return h


def _base(device: Device) -> str:
    return f"http://{device.host}:{device.port}"


def _not_a_client(device: Device, body: str) -> str:
    """Explain a 200 that is not the TVMaestro control API (often another app on the same port)."""
    where = f"{device.name} ({device.host}:{device.port})"
    match = _HTML_TITLE.search(body or "")
    if match:
        title = re.sub(r"\s+", " ", match.group(1)).strip()
        if title:
            return (
                f"{where} is not running the TVMaestro client. "
                f'Port {device.port} answered with "{title}". '
                "Open TVMaestro on that device and set this device's port to the app's control port."
            )
    snippet = " ".join((body or "").split())[:80]
    if snippet:
        return (
            f"{where} did not return JSON from the TVMaestro client "
            f"(got: {snippet}). Open the TVMaestro app and confirm the port."
        )
    return (
        f"{where} returned an empty response instead of the TVMaestro client API. "
        "Open the TVMaestro app and confirm the port."
    )


def read_json(resp: httpx.Response, device: Device) -> Any:
    resp.raise_for_status()
    try:
        return resp.json()
    except json.JSONDecodeError as exc:
        raise RuntimeError(_not_a_client(device, resp.text)) from exc


async def health(device: Device, timeout: float = 3.0) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(f"{_base(device)}/api/health", headers=_headers(device))
        return read_json(resp, device)


async def info(device: Device, timeout: float = 5.0) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(f"{_base(device)}/api/info", headers=_headers(device))
        return read_json(resp, device)


async def notify_guide_link(device: Device) -> None:
    """Tell an Apple TV client whether the guide has registered and paired it."""
    if not appletv_remote.is_apple_tv(device):
        return
    payload = {
        "registered": True,
        "paired": appletv_remote.has_credentials(device.id),
        "name": device.name,
    }
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            resp = await client.post(
                f"{_base(device)}/api/guide",
                headers=_headers(device),
                json=payload,
            )
            resp.raise_for_status()
    except Exception as exc:  # noqa: BLE001
        logger.debug("Apple TV guide status not delivered to %s: %s", device.host, exc)


async def _client_listening(device: Device, timeout: float = 1.5) -> bool:
    """True when something answers the control port, including an auth challenge."""
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.get(f"{_base(device)}/api/health", headers=_headers(device))
        return resp.status_code < 500
    except Exception:  # noqa: BLE001
        return False


async def _wait_for_client(device: Device, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if await _client_listening(device, timeout=2):
            return True
        await asyncio.sleep(0.5)
    return False


async def ensure_appletv_running(device: Device) -> None:
    """Launch the tvOS app when a tune arrives and the control API is down."""
    if not appletv_remote.is_apple_tv(device):
        return
    if await _client_listening(device):
        return
    if not appletv_remote.has_credentials(device.id):
        raise RuntimeError(
            f"{device.name} is not running the TVMaestro app. "
            "Pair the Apple TV in Edit device so the guide can open it, "
            "or open TVMaestro with the Siri Remote."
        )
    try:
        await appletv_remote.open_app(device)
    except appletv_remote.RemoteNotPaired as exc:
        raise RuntimeError(str(exc)) from exc
    except appletv_remote.RemoteUnavailable as exc:
        raise RuntimeError(str(exc)) from exc
    if not await _wait_for_client(device, timeout=20):
        raise RuntimeError(
            f"TVMaestro was asked to open on {device.name}, but the app never started "
            f"listening on port {device.port}. Confirm the app is installed and the Apple TV is awake."
        )


async def open_appletv_app(device: Device) -> None:
    """Bring TVMaestro to the front, then wait until its control API answers."""
    if not appletv_remote.is_apple_tv(device):
        raise RuntimeError("Open app is only available for Apple TV")
    try:
        await appletv_remote.open_app(device)
    except appletv_remote.RemoteNotPaired:
        raise
    except appletv_remote.RemoteUnavailable:
        raise
    if not await _wait_for_client(device, timeout=20):
        raise RuntimeError(
            f"TVMaestro was asked to open on {device.name}, but the app never started "
            f"listening on port {device.port}. Confirm the app is installed and the Apple TV is awake."
        )


async def push_session(device: Device, session: SessionState, timeout: float = 15.0) -> dict[str, Any]:
    await ensure_appletv_running(device)
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
        data = read_json(resp, device)
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
        return read_json(resp, device)


async def get_session(device: Device, timeout: float = 5.0) -> Optional[dict[str, Any]]:
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.get(f"{_base(device)}/api/session", headers=_headers(device))
        return read_json(resp, device)


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


async def appletv_power(device: Device, *, on: bool) -> dict[str, Any]:
    """Wake or sleep a paired Apple TV over Companion. Does not use adb or client HTTP."""
    action = "power_on" if on else "power_off"
    if not appletv_remote.has_credentials(device.id):
        return {
            "success": False,
            "action": action,
            "method": "appletv_companion",
            "message": (
                "Pair this Apple TV first (Edit device → Pair). A PIN appears on the Apple TV."
            ),
        }
    try:
        await appletv_remote.set_power(device, on=on)
    except appletv_remote.RemoteError as exc:
        return {
            "success": False,
            "action": action,
            "method": "appletv_companion",
            "message": str(exc),
        }
    verb = "wake" if on else "sleep"
    return {
        "success": True,
        "action": action,
        "method": "appletv_companion",
        "message": (
            f"Apple TV Companion {verb}. The television follows only if "
            "Control TVs and Receivers is on."
        ),
    }


async def appletv_volume(device: Device, action: CecAction) -> dict[str, Any]:
    """Volume and mute for Apple TV: Companion HID, same keys as the Siri Remote."""
    if not appletv_remote.has_credentials(device.id):
        return {
            "success": False,
            "action": action.value,
            "method": "appletv_companion",
            "message": (
                "Pair this Apple TV first (Edit device → Pair). "
                "A PIN appears on the Apple TV. Volume then follows the Siri Remote."
            ),
        }
    try:
        await appletv_remote.adjust_volume(device, action.value)
    except appletv_remote.RemoteError as exc:
        return {
            "success": False,
            "action": action.value,
            "method": "appletv_companion",
            "message": str(exc),
        }
    labels = {
        CecAction.volume_up: "Volume up",
        CecAction.volume_down: "Volume down",
        CecAction.mute: "Mute",
    }
    return {
        "success": True,
        "action": action.value,
        "method": "appletv_companion",
        "message": (
            f"{labels.get(action, action.value)} sent the same way as the Siri Remote. "
            "The television follows only if Control TVs and Receivers is on."
        ),
    }


async def cec(device: Device, action: CecAction, timeout: float = 5.0) -> dict[str, Any]:
    """Send CEC / power action.

    Volume/mute → Android AudioManager, or Apple TV Companion (Siri Remote keys).

    Wake/Sleep:
      Apple TV → Companion turn_on / turn_off when paired
      Android:
        1. Android TV Remote (paired) — no ADB
        2. adb WAKEUP/SLEEP — fallback when unpaired or remote fails
        3. Client HTTP (rarely works for power on Shield)
    """
    if appletv_remote.is_apple_tv(device) and action in (
        CecAction.volume_up,
        CecAction.volume_down,
        CecAction.mute,
    ):
        return await appletv_volume(device, action)

    if action in (CecAction.power_on, CecAction.power_off):
        on = action == CecAction.power_on
        if appletv_remote.is_apple_tv(device):
            return await appletv_power(device, on=on)
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
            result = read_json(resp, device)
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
