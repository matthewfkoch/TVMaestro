"""The new default must not rewrite ports in an existing device registry."""

import asyncio
import json

import pytest

from tvmaestro.devices import DeviceRegistry
from tvmaestro.models import DeviceCreate, DeviceUpdate


@pytest.mark.parametrize("port", [9093, 12000])
def test_upgrade_preserves_registered_port(tmp_path, monkeypatch, port):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    (tmp_path / "devices.json").write_text(json.dumps({"devices": [{
        "id": "existing", "name": "TV", "host": "10.0.0.8", "port": port,
        "token": "saved-token",
    }]}))
    registry = DeviceRegistry()
    assert registry.get("existing").port == port
    asyncio.run(registry.update("existing", DeviceUpdate(name="Renamed TV")))
    reloaded = DeviceRegistry().get("existing")
    assert reloaded.port == port
    assert reloaded.token == "saved-token"


def test_new_registration_uses_new_port_and_can_be_corrected(tmp_path, monkeypatch):
    monkeypatch.setenv("TVMAESTRO_DATA_DIR", str(tmp_path))
    registry = DeviceRegistry()
    device = asyncio.run(registry.add(DeviceCreate(name="TV", host="10.0.0.8")))
    assert device.port == 6791
    assert DeviceRegistry().get(device.id).port == 6791
    asyncio.run(registry.update(device.id, DeviceUpdate(port=9093)))
    assert DeviceRegistry().get(device.id).port == 9093
