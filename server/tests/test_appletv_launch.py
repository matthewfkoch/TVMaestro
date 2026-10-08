"""Apple TV app launch: identity, pairing route, and tune-time open."""

from __future__ import annotations

import asyncio

import pytest

from tvmaestro import appletv_remote, client_proxy
from tvmaestro.models import Device, DeviceCapabilities


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
