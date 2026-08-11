"""Shared fixtures: isolated data dir + no real network during API tests."""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from tvmaestro.models import Channel, DeviceCapabilities


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))

    async def _noop_refresh(self):  # noqa: ANN001
        return None

    async def _noop_loop(self):  # noqa: ANN001
        return None

    async def _poll_one(self, device_id: str):  # noqa: ANN001
        return self.get(device_id)

    with (
        patch("tvmaestro.guide.GuideStore.refresh", new=_noop_refresh),
        patch("tvmaestro.guide.GuideStore._loop", new=_noop_loop),
        patch("tvmaestro.devices.DeviceRegistry.poll_one", new=_poll_one),
        patch("tvmaestro.devices.DeviceRegistry._heartbeat_loop", new=_noop_loop),
        patch(
            "tvmaestro.client_proxy.push_session",
            new=AsyncMock(return_value={"success": True}),
        ),
        patch(
            "tvmaestro.client_proxy.stop_session",
            new=AsyncMock(return_value={"ok": True}),
        ),
    ):
        from tvmaestro.main import app

        with TestClient(app) as test_client:
            yield test_client


@pytest.fixture
def registered_device(client: TestClient):
    """Register a device with multiview capacity for session tests."""
    resp = client.post(
        "/api/devices",
        json={"name": "Test TV", "host": "127.0.0.1", "port": 9093},
    )
    assert resp.status_code == 200, resp.text
    device = resp.json()
    registry = client.app.state.devices
    stored = registry.get(device["id"])
    assert stored is not None
    stored.capabilities = DeviceCapabilities(
        multiview_max=4,
        layouts=["1", "2x1", "1x2", "2x2"],
    )
    registry._devices[stored.id] = stored
    return stored


@pytest.fixture
def seeded_channels(client: TestClient):
    guide = client.app.state.guide
    guide.channels = [
        Channel(
            id="espn",
            name="ESPN",
            number="206",
            url="http://dvr.example/espn.ts",
        ),
        Channel(
            id="cnn",
            name="CNN",
            number="202",
            url="http://dvr.example/cnn.ts",
        ),
    ]
    return guide.channels
