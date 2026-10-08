"""Sessions keep the original MPEG-TS URL for both clients."""

TS = "http://192.168.1.17:8089/devices/ANY/channels/2.1/stream.mpg?format=ts&codec=copy"


def test_apple_tv_session_keeps_the_original_mpeg_ts_url(client):
    created = client.post(
        "/api/devices",
        json={"name": "Den", "host": "10.0.0.8", "platform": "tvos"},
    ).json()
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": created["id"],
            "mode": "single",
            "layout": "1",
            "slots": [{"url": TS, "title": "FOX", "audio": True}],
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["slots"][0]["url"] == TS


def test_android_session_keeps_mpeg_ts(client, registered_device):
    resp = client.post(
        "/api/sessions",
        json={
            "device_id": registered_device.id,
            "mode": "single",
            "layout": "1",
            "slots": [{"url": TS, "audio": True}],
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["slots"][0]["url"] == TS
