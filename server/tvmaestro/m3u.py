"""Parse M3U / M3U8 playlists into Channel models."""

from __future__ import annotations

import logging
import re
from typing import Literal
from urllib.parse import unquote

from .models import Channel

logger = logging.getLogger(__name__)

ChannelSource = Literal["channels", "apituner", "youtube"]

EXTINF_RE = re.compile(r"#EXTINF:(-?\d+)(?:\s+(.*))?", re.IGNORECASE)
ATTR_RE = re.compile(r'([A-Za-z0-9_-]+)="([^"]*)"')


def _attrs(fragment: str | None) -> dict[str, str]:
    if not fragment:
        return {}
    return {m.group(1).lower(): m.group(2) for m in ATTR_RE.finditer(fragment)}


def _display_name(attrs: dict[str, str], remainder: str) -> str:
    # EXTINF: duration attrs...,Name
    if "," in remainder:
        name = remainder.rsplit(",", 1)[-1].strip()
        if name:
            return name
    return attrs.get("tvg-name") or attrs.get("channel-name") or "Unknown"


def _channel_id(attrs: dict[str, str], name: str, number: str | None, index: int) -> str:
    for key in ("tvg-id", "channel-id", "tvc-guide-stationid"):
        if attrs.get(key):
            return attrs[key]
    if number:
        return f"ch-{number}"
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", name).strip("-").lower() or f"idx-{index}"
    return slug


def parse_m3u(text: str, *, source: ChannelSource = "channels") -> list[Channel]:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    channels: list[Channel] = []
    i = 0
    index = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("#EXTINF"):
            m = EXTINF_RE.match(line)
            attrs_blob = ""
            if m:
                attrs_blob = m.group(2) or ""
            attrs = _attrs(attrs_blob)
            name = _display_name(attrs, attrs_blob)
            number = attrs.get("tvg-chno") or attrs.get("channel-number") or attrs.get("chno")
            logo = attrs.get("tvg-logo") or attrs.get("logo")
            group = attrs.get("group-title")
            station = attrs.get("tvc-guide-stationid") or attrs.get("tvg-id")
            # Skip EXT* tags until URL
            i += 1
            while i < len(lines) and lines[i].startswith("#"):
                i += 1
            if i >= len(lines):
                break
            url = lines[i].strip()
            if url.startswith("#"):
                i += 1
                continue
            ch_id = _channel_id(attrs, name, number, index)
            channels.append(
                Channel(
                    id=ch_id,
                    number=number,
                    name=unquote(name),
                    logo=logo,
                    group=group,
                    url=url,
                    station_id=station,
                    source=source,
                )
            )
            index += 1
        i += 1
    logger.info("Parsed %d channels from M3U", len(channels))
    return channels
