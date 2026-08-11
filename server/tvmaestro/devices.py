"""Device registry with heartbeat polling."""

from __future__ import annotations

import asyncio
import json
import logging
import shutil
import time
import uuid
from pathlib import Path
from typing import Optional

from . import client_proxy
from . import androidtv_remote
from .config import data_dir
from .models import CecCapabilities, Device, DeviceCapabilities, DeviceCreate, DeviceUpdate

logger = logging.getLogger(__name__)


def _adb_available() -> bool:
    return shutil.which("adb") is not None


class DeviceRegistry:
    def __init__(self) -> None:
        self._devices: dict[str, Device] = {}
        self._path = data_dir() / "devices.json"
        self._lock = asyncio.Lock()
        self._task: asyncio.Task | None = None
        self._load()

    def _load(self) -> None:
        if not self._path.exists():
            return
        try:
            raw = json.loads(self._path.read_text(encoding="utf-8"))
            for item in raw.get("devices", []):
                d = Device.model_validate(item)
                self._devices[d.id] = d
        except Exception as exc:  # noqa: BLE001
            logger.warning("Failed to load devices: %s", exc)

    def _save(self) -> None:
        payload = {"devices": [d.model_dump() for d in self._devices.values()]}
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    async def start(self) -> None:
        self._task = asyncio.create_task(self._heartbeat_loop(), name="device-heartbeat")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _heartbeat_loop(self) -> None:
        while True:
            await self.poll_all()
            await asyncio.sleep(10)

    async def poll_all(self) -> None:
        for device_id in list(self._devices.keys()):
            await self.poll_one(device_id)

    async def poll_one(self, device_id: str) -> Optional[Device]:
        device = self._devices.get(device_id)
        if not device:
            return None
        try:
            await client_proxy.health(device)
            info = await client_proxy.info(device)
            caps_raw = info.get("capabilities") or info.get("cec") or {}
            cec_raw = caps_raw.get("cec") if isinstance(caps_raw.get("cec"), dict) else caps_raw
            if not isinstance(cec_raw, dict):
                cec_raw = {}
            # Wake/Sleep: Android TV Remote (paired) or adb; client HDMI often blocked.
            # Apple TV / tvOS has no adb or ATV-remote path — trust the client's cec.power flag.
            platform = str(info.get("platform") or caps_raw.get("platform") or "").lower()
            is_apple_tv = platform in ("tvos", "appletv") or str(
                caps_raw.get("chip_family") or info.get("chip_family") or ""
            ).lower() in ("apple", "appletv")
            client_power = bool(cec_raw.get("power", False))
            remote_paired = False if is_apple_tv else androidtv_remote.has_certs(device_id)
            adb_power = False if is_apple_tv else _adb_available()
            if remote_paired:
                method = "androidtv_remote"
            elif client_power:
                method = str(cec_raw.get("method", "keys"))
            elif adb_power:
                method = "adb"
            else:
                method = str(cec_raw.get("method", "keys"))
            cec = CecCapabilities(
                power=client_power or remote_paired or adb_power,
                volume=bool(cec_raw.get("volume", True)),
                mute=bool(cec_raw.get("mute", True)),
                method=method,
            )
            device.online = True
            device.last_seen = time.time()
            device.model = info.get("model") or device.model
            device.manufacturer = info.get("manufacturer") or device.manufacturer
            device.android_version = (
                str(info.get("androidVersion") or info.get("android_version") or "")
                or device.android_version
            )
            device.capabilities = DeviceCapabilities(
                multiview_max=int(caps_raw.get("multiview_max", 1)),
                layouts=list(caps_raw.get("layouts") or ["1"]),
                cec=cec,
                mpeg_ts=bool(caps_raw.get("mpeg_ts", True)),
                hls=bool(caps_raw.get("hls", True)),
                weak_decoder=bool(caps_raw.get("weak_decoder", True)),
                chip_family=str(
                    caps_raw.get("chip_family")
                    or info.get("chip_family")
                    or "unknown"
                ),
                chip_note=str(caps_raw.get("chip_note") or ""),
            )
            self._devices[device_id] = device
            self._save()
        except Exception as exc:  # noqa: BLE001
            logger.debug("Device %s offline: %s", device_id, exc)
            was_online = device.online
            device.online = False
            self._devices[device_id] = device
            if was_online:
                self._save()
        return device

    def list(self) -> list[Device]:
        return sorted(self._devices.values(), key=lambda d: d.name.lower())

    def get(self, device_id: str) -> Optional[Device]:
        return self._devices.get(device_id)

    def add(self, body: DeviceCreate) -> Device:
        device_id = body.id or str(uuid.uuid4())
        device = Device(
            id=device_id,
            name=body.name,
            host=body.host,
            port=body.port,
            token=body.token,
        )
        self._devices[device_id] = device
        self._save()
        return device

    def update(self, device_id: str, body: DeviceUpdate) -> Optional[Device]:
        device = self._devices.get(device_id)
        if not device:
            return None
        data = device.model_dump()
        patch = body.model_dump(exclude_unset=True)
        data.update(patch)
        device = Device.model_validate(data)
        self._devices[device_id] = device
        self._save()
        return device

    def delete(self, device_id: str) -> bool:
        if device_id not in self._devices:
            return False
        del self._devices[device_id]
        self._save()
        androidtv_remote.clear_certs(device_id)
        return True
