from tvmaestro.secrets import (
    REDACTED,
    drop_unchanged_secrets,
    public_config,
    public_device,
)


def test_public_config_redacts_tokens():
    data = public_config(
        {
            "apituner_auth_token": "secret",
            "client_auth_token": "other",
            "apituner_base_url": "http://x",
        }
    )
    assert data["apituner_auth_token"] == REDACTED
    assert data["client_auth_token"] == REDACTED
    assert data["apituner_base_url"] == "http://x"


def test_drop_unchanged_secrets():
    updates = drop_unchanged_secrets(
        {"apituner_auth_token": REDACTED, "apituner_base_url": "http://y"}
    )
    assert "apituner_auth_token" not in updates
    assert updates["apituner_base_url"] == "http://y"


def test_public_device_redacts_token():
    data = public_device({"id": "1", "token": "abc", "name": "Living room"})
    assert data["token"] == REDACTED
    assert data["name"] == "Living room"
