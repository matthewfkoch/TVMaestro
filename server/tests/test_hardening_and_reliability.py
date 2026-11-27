"""Tests for security hardening, reliability, caching, layout clamping, and pyatv contract."""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from tvmaestro import androidtv_remote, appletv_remote, client_proxy
from tvmaestro.config import ConfigStore, atomic_write_text
from tvmaestro.devices import DeviceRegistry
from tvmaestro.guide import GuideStore
from tvmaestro.models import (
    Channel,
    DeviceCreate,
)


def test_device_id_rejects_path_traversal(client: TestClient):
    for bad_id in ("../config", "a/b", "a\\b", "..", "has space", ""):
        resp = client.post(
            "/api/devices",
            json={"id": bad_id, "name": "Bad", "host": "10.0.0.5"},
        )
        assert resp.status_code == 422, f"expected 422 for id={bad_id!r}, got {resp.status_code}"


def test_remote_helpers_guard_unsafe_device_ids(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    assert androidtv_remote.has_certs("../escape") is False
    assert appletv_remote.has_credentials("../escape") is False
    with pytest.raises(ValueError):
        appletv_remote.storage_path("../escape")


def test_device_host_and_port_validation(client: TestClient):
    for bad_host in ("-s", "http://10.0.0.5", "10.0.0.5/evil", "10.0.0.5 extra", ""):
        resp = client.post(
            "/api/devices",
            json={"name": "Bad Host", "host": bad_host},
        )
        assert resp.status_code == 422, f"expected 422 for host={bad_host!r}"

    for bad_port in (0, -1, 65536):
        resp = client.post(
            "/api/devices",
            json={"name": "Bad Port", "host": "10.0.0.5", "port": bad_port},
        )
        assert resp.status_code == 422, f"expected 422 for port={bad_port}"


def test_adb_power_rejects_flag_like_host():
    assert asyncio.run(client_proxy.adb_power("-s evil", on=True)) is False
    assert asyncio.run(client_proxy.adb_power("  ", on=False)) is False


def test_config_refresh_interval_minimum(client: TestClient):
    resp = client.put("/api/config", json={"m3u_refresh_seconds": 0})
    assert resp.status_code == 422
    resp2 = client.put("/api/config", json={"xmltv_refresh_seconds": 5})
    assert resp2.status_code == 422


def test_client_auth_token_enforcement(client: TestClient):
    # Open when empty
    assert client.get("/api/devices").status_code == 200

    # Configure token
    put = client.put("/api/config", json={"client_auth_token": "s3cret"})
    assert put.status_code == 200

    # Status remains open for health checks / companion discovery
    assert client.get("/api/status").status_code == 200

    # Other API endpoints reject missing or wrong token
    assert client.get("/api/devices").status_code == 401
    assert client.get("/api/devices", headers={"X-Auth-Token": "wrong"}).status_code == 401

    # Valid X-Auth-Token or Bearer token succeeds
    assert client.get("/api/devices", headers={"X-Auth-Token": "s3cret"}).status_code == 200
    assert (
        client.get("/api/devices", headers={"Authorization": "Bearer s3cret"}).status_code == 200
    )


def test_cors_allows_capacitor_and_blocks_arbitrary_origin(client: TestClient):
    cap = client.get("/api/status", headers={"Origin": "capacitor://localhost"})
    assert cap.headers.get("access-control-allow-origin") == "capacitor://localhost"

    local = client.get("/api/status", headers={"Origin": "http://localhost:5173"})
    assert local.headers.get("access-control-allow-origin") == "http://localhost:5173"

    evil = client.get("/api/status", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in evil.headers


def test_atomic_write_text_replaces_cleanly(tmp_path):
    target = tmp_path / "state.json"
    atomic_write_text(target, '{"v": 1}\n')
    atomic_write_text(target, '{"v": 2}\n')
    assert target.read_text(encoding="utf-8") == '{"v": 2}\n'
    # No stray temp files left behind
    assert [p.name for p in tmp_path.iterdir()] == ["state.json"]


def test_guide_epg_disk_cache_persists_remapped_channel_ids(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    store = ConfigStore()
    store.update(
        channels_dvr_m3u_url="http://dvr.local/channels.m3u",
        channels_dvr_xmltv_url="http://dvr.local/epg.xml",
    )
    guide = GuideStore(store)
    guide.channels = [
        Channel(
            id="ch-espn",
            number="206",
            name="ESPN",
            url="http://dvr.local/espn.ts",
            station_id="station-999",
        )
    ]
    xmltv_payload = """<?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="station-999"><display-name>ESPN</display-name></channel>
      <programme start="20260101120000 +0000" stop="20260101130000 +0000" channel="station-999">
        <title>SportsCenter</title>
      </programme>
    </tv>"""

    class _FakeResp:
        text = xmltv_payload

        def raise_for_status(self) -> None:
            return None

    class _FakeClient:
        def __init__(self, *args: object, **kwargs: object) -> None:
            del args, kwargs

        async def __aenter__(self) -> "_FakeClient":
            return self

        async def __aexit__(self, *args: object) -> None:
            return None

        async def get(self, url: str) -> _FakeResp:
            del url
            return _FakeResp()

    monkeypatch.setattr(httpx, "AsyncClient", _FakeClient)
    asyncio.run(guide.refresh_epg())
    assert guide.programmes[0].channel_id == "ch-espn"

    # Reload from disk without channels populated yet — cached EPG already has remapped id
    reloaded = GuideStore(store)
    assert len(reloaded.programmes) == 1
    assert reloaded.programmes[0].channel_id == "ch-espn"


def test_multiview_clamps_grid3_to_device_max(client: TestClient, registered_device):
    # registered_device has multiview_max = 4
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "multiview",
            "layout": "3x3",
            "slots": [
                {"url": "http://dvr.example/a.ts", "audio": True},
                {"url": "http://dvr.example/b.ts", "audio": False},
            ],
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["layout"] == "2x2"

    # Clamp 3x3 on a 2-stream device to 2x1
    registered_device.capabilities.multiview_max = 2
    client.app.state.devices._devices[registered_device.id] = registered_device
    resp2 = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "multiview",
            "layout": "3x3",
            "slots": [
                {"url": "http://dvr.example/a.ts", "audio": True},
                {"url": "http://dvr.example/b.ts", "audio": False},
            ],
        },
    )
    assert resp2.status_code == 200, resp2.text
    assert resp2.json()["layout"] == "2x1"


def test_stopped_sessions_are_bounded_and_hydrate_recovers_live_session(
    client: TestClient, registered_device
):
    from tvmaestro.sessions import MAX_STOPPED_SESSIONS

    for i in range(MAX_STOPPED_SESSIONS + 10):
        created = client.post(
            "/api/sessions",
            json={
                "device_id": registered_device.id,
                "mode": "single",
                "layout": "1",
                "slots": [{"url": f"http://dvr.example/{i}.ts", "audio": True}],
            },
        )
        assert created.status_code == 200
        sid = created.json()["id"]
        assert client.post(f"/api/sessions/{sid}/stop").status_code == 200

    stopped = [s for s in client.get("/api/sessions").json() if s["status"] == "stopped"]
    assert len(stopped) == MAX_STOPPED_SESSIONS

    # Simulate restart recovery via hydrate_from_devices
    registered_device.online = True
    client.app.state.devices._devices[registered_device.id] = registered_device
    with patch(
        "tvmaestro.client_proxy.get_session",
        new=AsyncMock(
            return_value={
                "success": True,
                "session": {
                    "id": "recovered-1",
                    "layout": "2x1",
                    "slots": [
                        {"url": "http://dvr.example/a.ts", "title": "Alpha", "audio": True},
                        {"url": "http://dvr.example/b.ts", "title": "Beta", "audio": False},
                    ],
                },
            }
        ),
    ):
        asyncio.run(client.app.state.sessions.hydrate_from_devices())

    hydrated = client.get("/api/sessions/recovered-1")
    assert hydrated.status_code == 200
    assert hydrated.json()["status"] == "playing"
    assert hydrated.json()["layout"] == "2x1"


def test_device_heartbeat_avoids_redundant_disk_writes(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    registry = DeviceRegistry()
    device = asyncio.run(registry.add(DeviceCreate(name="Shield", host="10.0.0.12")))

    save_calls = 0
    original_save = registry._save

    def _counting_save() -> None:
        nonlocal save_calls
        save_calls += 1
        original_save()

    monkeypatch.setattr(registry, "_save", _counting_save)
    monkeypatch.setattr(client_proxy, "health", AsyncMock(return_value={"success": True}))
    monkeypatch.setattr(
        client_proxy,
        "info",
        AsyncMock(
            return_value={
                "model": "SHIELD Android TV",
                "manufacturer": "NVIDIA",
                "androidVersion": "11",
                "capabilities": {
                    "multiview_max": 4,
                    "layouts": ["1", "2x1", "1x2", "2x2"],
                    "chip_family": "nvidia_tegra",
                    "weak_decoder": False,
                    "cec": {"power": False, "volume": True, "mute": True, "method": "keys"},
                },
            }
        ),
    )

    # First poll transitions offline -> online: saves once
    asyncio.run(registry.poll_one(device.id))
    assert save_calls == 1

    # Second identical poll: should NOT rewrite devices.json
    asyncio.run(registry.poll_one(device.id))
    assert save_calls == 1


def test_pyatv_companion_hid_contract():
    """Guard private pyatv Companion HID API used by appletv_remote._send_volume."""
    from pyatv.protocols.companion import api as companion_api

    assert hasattr(companion_api, "CompanionAPI")
    assert hasattr(companion_api.CompanionAPI, "hid_command")
    assert hasattr(companion_api, "HidCommand")
    assert companion_api.HidCommand.VolumeUp.value == 8
    assert companion_api.HidCommand.VolumeDown.value == 9
