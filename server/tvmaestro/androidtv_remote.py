"""Android TV Remote protocol v2 (ADB-free Wake/Sleep).

Uses androidtvremote2 — the same protocol as the Google TV remote app.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path
from typing import Any, Optional

from .config import data_dir
from .models import Device

logger = logging.getLogger(__name__)

CLIENT_NAME = "TVMaestro"
DEFAULT_API_PORT = 6466
DEFAULT_PAIR_PORT = 6467


class RemoteError(Exception):
    """Base error for Android TV Remote operations."""


class RemoteNotPaired(RemoteError):
    """Device has not completed PIN pairing."""


class RemoteUnavailable(RemoteError):
    """Cannot reach the device remote service."""


def certs_dir() -> Path:
    path = data_dir() / "remote_certs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def has_certs(device_id: str) -> bool:
    base = certs_dir()
    return (base / f"{device_id}.crt").is_file() and (base / f"{device_id}.key").is_file()


def clear_certs(device_id: str) -> None:
    base = certs_dir()
    for suffix in (".crt", ".key"):
        path = base / f"{device_id}{suffix}"
        try:
            path.unlink(missing_ok=True)
        except OSError as exc:
            logger.warning("Failed to remove remote cert %s: %s", path, exc)


class AndroidTvRemoteClient:
    """One paired Android TV / Google TV / Shield endpoint."""

    def __init__(
        self,
        device: Device,
        *,
        api_port: int = DEFAULT_API_PORT,
        pair_port: int = DEFAULT_PAIR_PORT,
    ) -> None:
        self.device_id = device.id
        self.host = device.host
        self.api_port = api_port
        self.pair_port = pair_port
        base = certs_dir()
        self._certfile = str(base / f"{device.id}.crt")
        self._keyfile = str(base / f"{device.id}.key")
        self._remote: Any = None
        self._connected = False
        self._lock = asyncio.Lock()

    def _build(self) -> Any:
        from androidtvremote2 import AndroidTVRemote

        return AndroidTVRemote(
            client_name=CLIENT_NAME,
            certfile=self._certfile,
            keyfile=self._keyfile,
            host=self.host,
            api_port=self.api_port,
            pair_port=self.pair_port,
            enable_ime=False,
        )

    async def connect(self) -> None:
        from androidtvremote2 import CannotConnect, InvalidAuth

        async with self._lock:
            if self._connected and self._remote is not None:
                return
            if self._remote is None:
                self._remote = self._build()
            await self._remote.async_generate_cert_if_missing()
            try:
                await self._remote.async_connect()
            except InvalidAuth as exc:
                self._connected = False
                raise RemoteNotPaired(f"{self.host} is not paired") from exc
            except CannotConnect as exc:
                self._connected = False
                raise RemoteUnavailable(f"Cannot reach {self.host}: {exc}") from exc
            self._remote.keep_reconnecting()
            self._connected = True

    async def close(self) -> None:
        async with self._lock:
            if self._remote is not None:
                try:
                    self._remote.disconnect()
                except Exception:  # noqa: BLE001
                    pass
            self._connected = False

    async def is_paired(self) -> bool:
        if not has_certs(self.device_id):
            return False
        try:
            await self.connect()
            return True
        except RemoteNotPaired:
            return False
        except Exception:  # noqa: BLE001
            # Unreachable ≠ unpaired; certs suggest a prior successful pair.
            return has_certs(self.device_id)

    async def start_pairing(self) -> None:
        async with self._lock:
            self._connected = False
            self._remote = self._build()
            await self._remote.async_generate_cert_if_missing()
            await self._remote.async_start_pairing()

    async def finish_pairing(self, pin: str) -> None:
        async with self._lock:
            if self._remote is None:
                raise RemoteUnavailable("Pairing was not started")
            await self._remote.async_finish_pairing(pin.strip())
            await self._remote.async_connect()
            self._remote.keep_reconnecting()
            self._connected = True

    async def send_key(self, key: str) -> None:
        await self.connect()
        self._remote.send_key_command(key)

    async def power(self, *, on: bool) -> None:
        """Wake or sleep via remote keys (CEC TV follows when Power Control is on)."""
        # WAKEUP / SLEEP map cleanly; POWER as last resort if library rejects them.
        primary = "WAKEUP" if on else "SLEEP"
        fallback = "POWER"
        try:
            await self.send_key(primary)
        except Exception as exc:  # noqa: BLE001
            logger.debug("remote %s failed (%s); trying %s", primary, exc, fallback)
            await self.send_key(fallback)


class RemoteRegistry:
    """Cache remote clients keyed by device id (host changes rebuild the client)."""

    def __init__(self) -> None:
        self._clients: dict[str, AndroidTvRemoteClient] = {}
        self._lock = asyncio.Lock()

    async def get(self, device: Device) -> AndroidTvRemoteClient:
        async with self._lock:
            existing = self._clients.get(device.id)
            if existing is not None and existing.host == device.host:
                return existing
            if existing is not None:
                await existing.close()
            client = AndroidTvRemoteClient(device)
            self._clients[device.id] = client
            return client

    async def drop(self, device_id: str) -> None:
        async with self._lock:
            client = self._clients.pop(device_id, None)
            if client:
                await client.close()


_registry: Optional[RemoteRegistry] = None


def remotes() -> RemoteRegistry:
    global _registry
    if _registry is None:
        _registry = RemoteRegistry()
    return _registry
