"""Open the TVMaestro app on an Apple TV over the Companion remote protocol.

tvOS will not keep a LAN control server alive in the background. After a one-time
PIN pairing, the guide can wake the Apple TV and launch com.tvmaestro.client.
The television set itself still follows only if that Apple TV's HDMI-CEC wake is on.
"""

from __future__ import annotations

import asyncio
import logging
import socket
from ipaddress import IPv4Address
from pathlib import Path
from typing import Any, Optional

from .config import data_dir
from .models import Device

logger = logging.getLogger(__name__)

BUNDLE_ID = "com.tvmaestro.client"
CLIENT_NAME = "TVMaestro"
SCAN_TIMEOUT = 5


class RemoteError(Exception):
    """Base error for Apple TV Companion operations."""


class RemoteNotPaired(RemoteError):
    """Device has not completed PIN pairing."""


class RemoteUnavailable(RemoteError):
    """Cannot reach the Apple TV Companion service."""


def _dir() -> Path:
    path = data_dir() / "appletv"
    path.mkdir(parents=True, exist_ok=True)
    return path


def storage_path(device_id: str) -> Path:
    return _dir() / f"{device_id}.conf"


def _marker_path(device_id: str) -> Path:
    return _dir() / f"{device_id}.paired"


def has_credentials(device_id: str) -> bool:
    return _marker_path(device_id).is_file() and storage_path(device_id).is_file()


def clear_credentials(device_id: str) -> None:
    for path in (storage_path(device_id), _marker_path(device_id)):
        try:
            path.unlink(missing_ok=True)
        except OSError as exc:
            logger.warning("Failed to remove Apple TV credential %s: %s", path, exc)


def is_apple_tv(device: Device) -> bool:
    """True once the client has identified itself, or the device was added as Apple TV.

    A known non-apple chip family wins over a stale manufacturer or meta flag,
    so a device added as Apple TV and later reached as Android is not launched
    with the Companion protocol.
    """
    family = (device.capabilities.chip_family or "").lower()
    manufacturer = (device.manufacturer or "").lower()
    if family in {"apple", "appletv"}:
        return True
    if family not in {"", "unknown"}:
        return False
    if manufacturer == "apple":
        return True
    if manufacturer:
        return False
    return str(device.meta.get("platform") or "").lower() in {"tvos", "appletv"}


def _ipv4(host: str) -> str:
    candidate = host.strip()
    try:
        return str(IPv4Address(candidate))
    except ValueError:
        pass
    try:
        infos = socket.getaddrinfo(candidate, None, socket.AF_INET)
    except socket.gaierror as exc:
        raise RemoteUnavailable(f"Cannot resolve {candidate}") from exc
    for info in infos:
        addr = info[4][0]
        try:
            return str(IPv4Address(addr))
        except ValueError:
            continue
    raise RemoteUnavailable(f"No IPv4 address for {candidate}")


async def _close_atv(atv: Any) -> None:
    closer = getattr(atv, "close", None)
    if closer is None:
        return
    result = closer()
    if asyncio.iscoroutine(result):
        await result


class AppleTvRemoteClient:
    """One Apple TV endpoint. Pairing state is held between the PIN start and finish calls."""

    def __init__(self, device: Device) -> None:
        self.device_id = device.id
        self.host = device.host
        self._lock = asyncio.Lock()
        self._pairing: Any = None
        self._storage: Any = None

    async def close(self) -> None:
        async with self._lock:
            await self._close_pairing()

    async def _close_pairing(self) -> None:
        pairing = self._pairing
        self._pairing = None
        self._storage = None
        if pairing is None:
            return
        try:
            await pairing.close()
        except Exception:  # noqa: BLE001
            logger.debug("Apple TV pairing close failed", exc_info=True)

    async def _load_storage(self, loop: asyncio.AbstractEventLoop) -> Any:
        from pyatv.storage.file_storage import FileStorage

        storage = FileStorage(str(storage_path(self.device_id)), loop)
        await storage.load()
        return storage

    async def _scan(self, loop: asyncio.AbstractEventLoop, storage: Any) -> Any:
        import pyatv
        from pyatv.const import Protocol

        host = await asyncio.to_thread(_ipv4, self.host)
        found = await pyatv.scan(
            loop,
            timeout=SCAN_TIMEOUT,
            hosts=[host],
            protocol=Protocol.Companion,
            storage=storage,
        )
        if not found:
            raise RemoteUnavailable(
                f"No Apple TV answered at {self.host}. Wake it with the Siri Remote and try again."
            )
        return found[0]

    async def start_pairing(self) -> None:
        import pyatv
        from pyatv.const import Protocol

        async with self._lock:
            await self._close_pairing()
            loop = asyncio.get_running_loop()
            storage = await self._load_storage(loop)
            pairing = None
            try:
                config = await self._scan(loop, storage)
                pairing = await pyatv.pair(
                    config,
                    Protocol.Companion,
                    loop,
                    storage=storage,
                    name=CLIENT_NAME,
                )
                await pairing.begin()
            except RemoteError:
                if pairing is not None:
                    await pairing.close()
                raise
            except Exception as exc:  # noqa: BLE001
                if pairing is not None:
                    await pairing.close()
                raise RemoteUnavailable(f"Could not start pairing with {self.host}: {exc}") from exc
            self._pairing = pairing
            self._storage = storage
            logger.info("Apple TV pairing PIN requested on %s", self.host)

    async def finish_pairing(self, pin: str) -> None:
        async with self._lock:
            pairing = self._pairing
            storage = self._storage
            if pairing is None or storage is None:
                raise RemoteUnavailable("Pairing was not started")
            code = "".join(pin.split())
            if not code:
                raise RemoteUnavailable("PIN is required")
            try:
                pairing.pin(code)
                await pairing.finish()
                if not pairing.has_paired:
                    raise RemoteUnavailable("Apple TV did not accept that PIN")
                await storage.save()
            except RemoteError:
                raise
            except Exception as exc:  # noqa: BLE001
                raise RemoteUnavailable(f"Apple TV pairing failed: {exc}") from exc
            _marker_path(self.device_id).write_text("ok\n", encoding="utf-8")
            await self._close_pairing()
            logger.info("Apple TV paired: %s", self.host)

    async def launch_app(self) -> None:
        if not has_credentials(self.device_id):
            raise RemoteNotPaired(
                "Pair this Apple TV first (Edit device → Pair). A PIN appears on the TV."
            )
        import pyatv

        async with self._lock:
            loop = asyncio.get_running_loop()
            storage = await self._load_storage(loop)
            atv = None
            try:
                config = await self._scan(loop, storage)
                atv = await pyatv.connect(config, loop, storage=storage)
                await self._wake(atv)
                await self._launch(atv)
            except RemoteError:
                raise
            except Exception as exc:  # noqa: BLE001
                message = str(exc).lower()
                if "auth" in message or "credential" in message:
                    raise RemoteNotPaired(
                        "Apple TV rejected the saved pairing. Pair it again from Edit device."
                    ) from exc
                raise RemoteUnavailable(f"Could not open TVMaestro on {self.host}: {exc}") from exc
            finally:
                if atv is not None:
                    await _close_atv(atv)

    async def _wake(self, atv: Any) -> None:
        power = getattr(atv, "power", None)
        turn_on = getattr(power, "turn_on", None)
        if turn_on is None:
            return
        try:
            result = turn_on()
            if asyncio.iscoroutine(result):
                await result
        except Exception as exc:  # noqa: BLE001
            logger.debug("Apple TV wake before launch failed: %s", exc)

    async def _launch(self, atv: Any) -> None:
        try:
            await atv.apps.launch_app(BUNDLE_ID)
        except Exception as first:  # noqa: BLE001
            logger.info("Apple TV launch retry for %s: %s", BUNDLE_ID, first)
            await asyncio.sleep(1.5)
            await atv.apps.launch_app(BUNDLE_ID)
        logger.info("Asked %s to open %s", self.host, BUNDLE_ID)


class RemoteRegistry:
    def __init__(self) -> None:
        self._clients: dict[str, AppleTvRemoteClient] = {}
        self._lock = asyncio.Lock()

    async def get(self, device: Device) -> AppleTvRemoteClient:
        async with self._lock:
            existing = self._clients.get(device.id)
            if existing is not None and existing.host == device.host:
                return existing
            if existing is not None:
                await existing.close()
            client = AppleTvRemoteClient(device)
            self._clients[device.id] = client
            return client

    async def drop(self, device_id: str) -> None:
        async with self._lock:
            client = self._clients.pop(device_id, None)
        if client is not None:
            await client.close()


_registry: Optional[RemoteRegistry] = None


def remotes() -> RemoteRegistry:
    global _registry
    if _registry is None:
        _registry = RemoteRegistry()
    return _registry


async def open_app(device: Device) -> None:
    client = await remotes().get(device)
    await client.launch_app()
