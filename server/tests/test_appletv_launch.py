"""Apple TV app launch: identity, pairing route, and tune-time open."""

from __future__ import annotations

import asyncio

import pytest

from tvmaestro import appletv_remote, client_proxy
from tvmaestro.devices import DeviceRegistry
from tvmaestro.models import CecAction, CecCapabilities, Device, DeviceCapabilities


def _apple(**kwargs: object) -> Device:
    data = dict(
        id="apple-1",
        name="Den",
        host="10.0.0.8",
        manufacturer="Apple",
        capabilities=DeviceCapabilities(chip_family="apple", mpeg_ts=False, hls=True),
    )
    data.update(kwargs)
    return Device(**data)  # type: ignore[arg-type]


def test_is_apple_tv_uses_chip_family_over_stale_meta():
    apple = _apple()
    assert appletv_remote.is_apple_tv(apple)
    android = Device(
        id="stick",
        name="Stick",
        host="10.0.0.9",
        manufacturer="Apple",
        meta={"platform": "tvos"},
        capabilities=DeviceCapabilities(chip_family="amlogic"),
    )
    assert not appletv_remote.is_apple_tv(android)
    hinted = Device(id="x", name="x", host="10.0.0.3", meta={"platform": "tvos"})
    assert appletv_remote.is_apple_tv(hinted)


def test_create_apple_tv_seeds_identity_before_the_app_is_online(client):
    resp = client.post(
        "/api/devices",
        json={"name": "Den", "host": "10.0.0.8", "platform": "tvos"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["manufacturer"] == "Apple"
    assert body["capabilities"]["chip_family"] == "apple"
    assert body["capabilities"]["mpeg_ts"] is True
    assert body["capabilities"]["multiview_max"] == 9

    status = client.get(f"/api/devices/{body['id']}/pair/status")
    assert status.status_code == 200
    assert status.json()["method"] == "appletv_companion"
    assert status.json()["paired"] is False


def test_launch_requires_pairing(client):
    created = client.post(
        "/api/devices",
        json={"name": "Den", "host": "10.0.0.8", "platform": "tvos"},
    ).json()
    resp = client.post(f"/api/devices/{created['id']}/launch")
    assert resp.status_code == 409
    assert "Pair" in resp.json()["detail"]


def test_launch_rejects_android_devices(client, registered_device):
    resp = client.post(f"/api/devices/{registered_device.id}/launch")
    assert resp.status_code == 400


def test_pair_start_uses_companion_for_apple_tv(client, monkeypatch):
    created = client.post(
        "/api/devices",
        json={"name": "Den", "host": "10.0.0.8", "platform": "tvos"},
    ).json()
    started: list[str] = []

    class FakeRemote:
        async def start_pairing(self) -> None:
            started.append("apple")

    class Registry:
        async def get(self, device: Device) -> FakeRemote:
            assert device.id == created["id"]
            return FakeRemote()

    monkeypatch.setattr(appletv_remote, "remotes", lambda: Registry())
    resp = client.post(f"/api/devices/{created['id']}/pair/start")
    assert resp.status_code == 200, resp.text
    assert "Apple TV" in resp.json()["message"]
    assert started == ["apple"]


def test_ensure_skips_launch_when_the_app_is_already_listening(monkeypatch):
    opened: list[str] = []

    async def probe(device: Device, timeout: float = 1.5) -> bool:
        return True

    async def open_app(device: Device) -> None:
        opened.append(device.id)

    monkeypatch.setattr(client_proxy, "_client_listening", probe)
    monkeypatch.setattr(appletv_remote, "open_app", open_app)
    asyncio.run(client_proxy.ensure_appletv_running(_apple()))
    assert opened == []


def test_ensure_launches_when_the_app_is_closed(monkeypatch):
    calls = {"probe": 0, "open": 0}

    async def probe(device: Device, timeout: float = 1.5) -> bool:
        calls["probe"] += 1
        return calls["probe"] > 1

    async def open_app(device: Device) -> None:
        calls["open"] += 1

    monkeypatch.setattr(client_proxy, "_client_listening", probe)
    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: True)
    monkeypatch.setattr(appletv_remote, "open_app", open_app)
    asyncio.run(client_proxy.ensure_appletv_running(_apple()))
    assert calls["open"] == 1
    assert calls["probe"] >= 2


def test_ensure_explains_when_apple_tv_is_not_paired(monkeypatch):
    async def probe(device: Device, timeout: float = 1.5) -> bool:
        return False

    monkeypatch.setattr(client_proxy, "_client_listening", probe)
    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: False)
    with pytest.raises(RuntimeError, match="Pair the Apple TV"):
        asyncio.run(client_proxy.ensure_appletv_running(_apple()))


def test_paired_power_uses_companion_and_skips_adb(monkeypatch):
    calls: list[bool] = []

    async def set_power(device: Device, *, on: bool) -> None:
        calls.append(on)

    async def adb_power(host: str, *, on: bool) -> bool:
        raise AssertionError("adb")

    async def remote_power(device: Device, *, on: bool) -> bool:
        raise AssertionError("android remote")

    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: True)
    monkeypatch.setattr(appletv_remote, "set_power", set_power)
    monkeypatch.setattr(client_proxy, "adb_power", adb_power)
    monkeypatch.setattr(client_proxy, "remote_power", remote_power)

    wake = asyncio.run(client_proxy.cec(_apple(), CecAction.power_on))
    sleep = asyncio.run(client_proxy.cec(_apple(), CecAction.power_off))

    assert calls == [True, False]
    assert wake["success"] is True
    assert wake["method"] == "appletv_companion"
    assert wake["action"] == "power_on"
    assert sleep["success"] is True
    assert sleep["action"] == "power_off"
    assert sleep["method"] == "appletv_companion"


def test_apple_volume_uses_companion_not_player_gain(monkeypatch):
    seen: list[str] = []

    async def adjust_volume(device: Device, action: str) -> None:
        seen.append(action)

    class Boom:
        def __init__(self, *args: object, **kwargs: object) -> None:
            raise AssertionError("client http")

    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: True)
    monkeypatch.setattr(appletv_remote, "adjust_volume", adjust_volume)
    monkeypatch.setattr(client_proxy.httpx, "AsyncClient", Boom)

    result = asyncio.run(client_proxy.cec(_apple(), CecAction.volume_up))

    assert seen == ["volume_up"]
    assert result["success"] is True
    assert result["method"] == "appletv_companion"
    assert result["action"] == "volume_up"


def test_unpaired_apple_volume_asks_to_pair(monkeypatch):
    async def adjust_volume(device: Device, action: str) -> None:
        raise AssertionError(action)

    class Boom:
        def __init__(self, *args: object, **kwargs: object) -> None:
            raise AssertionError("client http")

    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: False)
    monkeypatch.setattr(appletv_remote, "adjust_volume", adjust_volume)
    monkeypatch.setattr(client_proxy.httpx, "AsyncClient", Boom)

    result = asyncio.run(client_proxy.cec(_apple(), CecAction.mute))

    assert result["success"] is False
    assert result["method"] == "appletv_companion"
    assert "Pair" in result["message"]


def test_companion_mute_uses_remote_hid_code():
    presses: list[tuple[bool, int]] = []

    class Api:
        async def hid_command(self, down: bool, command: object) -> None:
            presses.append((down, int(getattr(command, "value"))))

    class Remote:
        def __init__(self) -> None:
            self.api = Api()

    class RemoteControl:
        instances = [Remote()]

        async def volume_up(self) -> None:
            raise AssertionError("mute must not step volume")

        async def volume_down(self) -> None:
            raise AssertionError("mute must not step volume")

    class Atv:
        remote_control = RemoteControl()

    asyncio.run(appletv_remote._send_volume(Atv(), "mute"))
    assert presses == [(True, 18), (False, 18)]


def test_companion_volume_uses_remote_keys():
    presses: list[tuple[bool, int]] = []

    class Api:
        async def hid_command(self, down: bool, command: object) -> None:
            presses.append((down, int(getattr(command, "value"))))

    class Remote:
        def __init__(self) -> None:
            self.api = Api()

    class RemoteControl:
        instances = [Remote()]

    class Atv:
        remote_control = RemoteControl()

    asyncio.run(appletv_remote._send_volume(Atv(), "volume_up"))
    asyncio.run(appletv_remote._send_volume(Atv(), "volume_down"))
    assert presses == [(True, 8), (False, 8), (True, 9), (False, 9)]


def test_unpaired_power_asks_to_pair_and_skips_adb(monkeypatch):
    async def set_power(device: Device, *, on: bool) -> None:
        raise AssertionError("set_power")

    async def adb_power(host: str, *, on: bool) -> bool:
        raise AssertionError("adb")

    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: False)
    monkeypatch.setattr(appletv_remote, "set_power", set_power)
    monkeypatch.setattr(client_proxy, "adb_power", adb_power)

    result = asyncio.run(client_proxy.cec(_apple(), CecAction.power_off))
    assert result["success"] is False
    assert result["method"] == "appletv_companion"
    assert "Pair" in result["message"]


def test_paired_apple_tv_keeps_power_while_offline(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    registry = DeviceRegistry()
    device = _apple(
        online=True,
        capabilities=DeviceCapabilities(
            chip_family="apple",
            cec=CecCapabilities(power=False, volume=True, mute=True, method="player_gain"),
        ),
    )
    registry._devices[device.id] = device

    async def health(device: Device, timeout: float = 3.0) -> dict:
        raise RuntimeError("asleep")

    monkeypatch.setattr(client_proxy, "health", health)
    monkeypatch.setattr(appletv_remote, "has_credentials", lambda _device_id: True)

    first = asyncio.run(registry.poll_one(device.id))
    second = asyncio.run(registry.poll_one(device.id))
    assert first is not None and second is not None
    assert first.online is False
    assert second.online is False
    assert second.capabilities.cec.power is True
    assert second.capabilities.cec.method == "appletv_companion"
    assert second.capabilities.cec.volume is True
