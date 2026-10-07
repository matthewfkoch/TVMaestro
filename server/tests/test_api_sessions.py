"""API tests for status, devices, and session start/stop."""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient


def test_status(client: TestClient):
    resp = client.get("/api/status")
    assert resp.status_code == 200
    body = resp.json()
    assert "version" in body
    assert body["channels"] == 0
    assert body["devices_total"] == 0


def test_config_get_redacts_empty_secrets(client: TestClient):
    resp = client.get("/api/config")
    assert resp.status_code == 200
    body = resp.json()
    assert body["channels_dvr_m3u_url"] == ""
    assert body["channels_dvr_xmltv_url"] == ""
    assert body["client_auth_token"] == ""


def test_refresh_skips_unconfigured_guide_urls(client: TestClient):
    resp = client.post("/api/refresh")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


def test_list_sessions_empty(client: TestClient):
    resp = client.get("/api/sessions")
    assert resp.status_code == 200
    assert resp.json() == []


def test_create_session_unknown_device(client: TestClient):
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": "missing",
            "mode": "single",
            "layout": "1",
            "slots": [{"url": "http://example/stream.ts", "audio": True}],
        },
    )
    assert resp.status_code == 400
    assert "Unknown device" in resp.json()["detail"]


def test_create_session_requires_slot(client: TestClient, registered_device):
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "single",
            "layout": "1",
            "slots": [],
        },
    )
    assert resp.status_code == 400
    assert "At least one slot" in resp.json()["detail"]


def test_create_and_stop_session_by_url(client: TestClient, registered_device):
    create = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "single",
            "layout": "1",
            "slots": [
                {
                    "url": "http://dvr.example/live.ts",
                    "title": "Live",
                    "audio": True,
                }
            ],
        },
    )
    assert create.status_code == 200, create.text
    session = create.json()
    assert session["status"] == "playing"
    assert session["device_id"] == registered_device.id
    assert session["slots"][0]["url"] == "http://dvr.example/live.ts"
    assert session["slots"][0]["audio"] is True

    listed = client.get("/api/sessions")
    assert listed.status_code == 200
    assert len(listed.json()) == 1
    assert listed.json()[0]["id"] == session["id"]

    got = client.get(f"/api/sessions/{session['id']}")
    assert got.status_code == 200
    assert got.json()["id"] == session["id"]

    stop = client.post(f"/api/sessions/{session['id']}/stop")
    assert stop.status_code == 200
    assert stop.json()["status"] == "stopped"

    after = client.get("/api/sessions")
    assert after.json()[0]["status"] == "stopped"


def test_create_session_resolves_channel_id(
    client: TestClient, registered_device, seeded_channels
):
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "single",
            "layout": "1",
            "slots": [{"channel_id": "espn", "audio": True}],
        },
    )
    assert resp.status_code == 200, resp.text
    session = resp.json()
    assert session["slots"][0]["url"] == "http://dvr.example/espn.ts"
    assert session["slots"][0]["title"] == "ESPN"


def test_create_session_unknown_channel(client: TestClient, registered_device):
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "single",
            "layout": "1",
            "slots": [{"channel_id": "nope", "audio": True}],
        },
    )
    assert resp.status_code == 400
    assert "Unknown channel_id" in resp.json()["detail"]


def test_multiview_layout_and_single_audio(
    client: TestClient, registered_device, seeded_channels
):
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "multiview",
            "layout": "2x2",
            "slots": [
                {"channel_id": "espn", "audio": True},
                {"channel_id": None, "audio": False},
                {"channel_id": "cnn", "audio": True},
                {"channel_id": None, "audio": False},
            ],
        },
    )
    assert resp.status_code == 200, resp.text
    session = resp.json()
    assert session["mode"] == "multiview"
    assert session["layout"] == "2x2"
    assert len(session["slots"]) == 4
    assert [s["audio"] for s in session["slots"]] == [True, False, False, False]


def test_multiview_rejects_over_capacity(client: TestClient, registered_device):
    registered_device.capabilities.multiview_max = 1
    client.app.state.devices._devices[registered_device.id] = registered_device

    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "multiview",
            "layout": "2x1",
            "slots": [
                {"url": "http://dvr.example/a.ts", "audio": True},
                {"url": "http://dvr.example/b.ts", "audio": False},
            ],
        },
    )
    assert resp.status_code == 400
    assert "at most 1" in resp.json()["detail"]


def test_push_failure_returns_502(client: TestClient, registered_device):
    with patch(
        "tvmaestro.client_proxy.push_session",
        new=AsyncMock(side_effect=RuntimeError("device refused")),
    ):
        resp = client.post(
            "/api/sessions",
            json={
                "device_id": registered_device.id,
                "mode": "single",
                "layout": "1",
                "slots": [{"url": "http://dvr.example/live.ts", "audio": True}],
            },
        )
    assert resp.status_code == 502
    assert "device refused" in resp.json()["detail"]
    listed = client.get("/api/sessions")
    assert listed.status_code == 200
    assert listed.json() == []


def test_push_failure_keeps_prior_playing_session(client: TestClient, registered_device):
    first = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "single",
            "layout": "1",
            "slots": [{"url": "http://dvr.example/live.ts", "audio": True}],
        },
    )
    assert first.status_code == 200
    prior_id = first.json()["id"]

    with patch(
        "tvmaestro.client_proxy.push_session",
        new=AsyncMock(side_effect=RuntimeError("device refused")),
    ):
        resp = client.post(
            "/api/sessions",
            json={
                "device_id": registered_device.id,
                "mode": "single",
                "layout": "1",
                "slots": [{"url": "http://dvr.example/other.ts", "audio": True}],
            },
        )
    assert resp.status_code == 502
    listed = client.get("/api/sessions").json()
    current = [s for s in listed if s["status"] != "stopped"]
    assert len(current) == 1
    assert current[0]["id"] == prior_id
    assert current[0]["status"] == "playing"


def test_stop_missing_session(client: TestClient):
    resp = client.post("/api/sessions/does-not-exist/stop")
    assert resp.status_code == 404
