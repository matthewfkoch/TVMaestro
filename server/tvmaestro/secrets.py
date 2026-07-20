"""Helpers for redacting secrets in API responses."""

from __future__ import annotations

from typing import Any, Mapping, MutableMapping

REDACTED = "••••••••"

SECRET_CONFIG_KEYS = ("apituner_auth_token", "client_auth_token")


def redact_value(value: str | None) -> str:
    if value:
        return REDACTED
    return ""


def is_redacted(value: object) -> bool:
    return isinstance(value, str) and value == REDACTED


def public_config(data: Mapping[str, Any]) -> dict[str, Any]:
    out = dict(data)
    for key in SECRET_CONFIG_KEYS:
        if out.get(key):
            out[key] = REDACTED
    return out


def public_device(data: Mapping[str, Any]) -> dict[str, Any]:
    out = dict(data)
    if out.get("token"):
        out["token"] = REDACTED
    return out


def drop_unchanged_secrets(
    updates: MutableMapping[str, Any],
    *,
    keys: tuple[str, ...] = SECRET_CONFIG_KEYS,
) -> dict[str, Any]:
    """Remove secret fields that were echoed back unchanged (redacted)."""
    out = dict(updates)
    for key in keys:
        if key in out and is_redacted(out[key]):
            del out[key]
    return out
