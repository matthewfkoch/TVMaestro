"""Client control-plane responses that are not JSON."""

import asyncio

import httpx
import pytest

from tvmaestro import appletv_remote, client_proxy
from tvmaestro.client_proxy import read_json
from tvmaestro.models import Device, DeviceCapabilities


def _device() -> Device:
    return Device(id="d", name="Living Room", host="10.0.0.5", port=9093)


def _response(status: int, **kwargs: object) -> httpx.Response:
    return httpx.Response(
        status,
        request=httpx.Request("GET", "http://10.0.0.5:9093/api/health"),
        **kwargs,  # type: ignore[arg-type]
    )


def test_html_response_names_the_other_app():
    body = (
        "<!DOCTYPE html><html><head><title>ADB Auto-Enable Configuration</title></head>"
        "<body>config</body></html>"
    )
    resp = _response(200, text=body)
    with pytest.raises(RuntimeError, match="ADB Auto-Enable Configuration"):
        read_json(resp, _device())


def test_empty_response_is_not_a_json_parse_error():
    resp = _response(200, text="")
    with pytest.raises(RuntimeError, match="empty response"):
        read_json(resp, _device())


def test_json_body_is_returned():
    resp = _response(200, json={"success": True})
    assert read_json(resp, _device()) == {"success": True}


def test_guide_status_is_not_sent_to_android():
    android = Device(
        id="stick",
        name="Stick",
        host="10.0.0.9",
        capabilities=DeviceCapabilities(chip_family="amlogic"),
    )
    asyncio.run(client_proxy.notify_guide_link(android))


def test_guide_status_reports_saved_pairing(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    device = Device(
        id="apple-1",
        name="Living Room Apple TV",
        host="10.0.0.8",
        manufacturer="Apple",
        capabilities=DeviceCapabilities(chip_family="apple", mpeg_ts=False),
    )
    appletv_remote.storage_path(device.id).write_text("creds\n", encoding="utf-8")
    appletv_remote._marker_path(device.id).write_text("ok\n", encoding="utf-8")
    posted: dict[str, object] = {}

    class _Response:
        def raise_for_status(self) -> None:
            return None

    class _Client:
        def __init__(self, *args: object, **kwargs: object) -> None:
            del args, kwargs

        async def __aenter__(self) -> "_Client":
            return self

        async def __aexit__(self, *args: object) -> None:
            return None

        async def post(self, url: str, headers: object = None, json: object = None) -> _Response:
            del headers
            posted["url"] = url
            posted["json"] = json
            return _Response()

    monkeypatch.setattr(client_proxy.httpx, "AsyncClient", _Client)
    asyncio.run(client_proxy.notify_guide_link(device))
    assert posted["url"] == "http://10.0.0.8:9093/api/guide"
    assert posted["json"] == {
        "registered": True,
        "paired": True,
        "name": "Living Room Apple TV",
    }
