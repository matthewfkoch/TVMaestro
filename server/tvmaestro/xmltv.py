"""Parse XMLTV guide into Programme models."""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from typing import Optional
from xml.etree import ElementTree as ET

import defusedxml.ElementTree as DefusedET

from .models import Programme

logger = logging.getLogger(__name__)

# 20240714180000 +0000 or 20240714180000
XMLTV_TS = re.compile(
    r"^(\d{14})\s*([+-]\d{4}|[A-Z]{1,5})?$"
)


def parse_xmltv_time(value: str | None) -> Optional[int]:
    if not value:
        return None
    m = XMLTV_TS.match(value.strip())
    if not m:
        return None
    raw = m.group(1)
    tz = m.group(2) or "+0000"
    try:
        dt = datetime.strptime(raw, "%Y%m%d%H%M%S")
    except ValueError:
        return None
    if tz.startswith(("+", "-")) and len(tz) == 5:
        sign = 1 if tz[0] == "+" else -1
        hours = int(tz[1:3])
        mins = int(tz[3:5])
        offset = sign * (hours * 3600 + mins * 60)
        return int(dt.replace(tzinfo=timezone.utc).timestamp()) - offset
    # Named TZ (UTC/GMT) — treat as UTC
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def _text(el: ET.Element | None) -> Optional[str]:
    if el is None or el.text is None:
        return None
    text = el.text.strip()
    return text or None


def parse_xmltv(text: str) -> tuple[dict[str, str], list[Programme]]:
    """Return (xmltv_channel_id -> display name, programmes)."""
    root = DefusedET.fromstring(text)
    channel_names: dict[str, str] = {}
    for ch in root.findall("channel"):
        cid = ch.get("id")
        if not cid:
            continue
        display = _text(ch.find("display-name")) or cid
        channel_names[cid] = display

    programmes: list[Programme] = []
    for prog in root.findall("programme"):
        channel_id = prog.get("channel")
        start = parse_xmltv_time(prog.get("start"))
        stop = parse_xmltv_time(prog.get("stop"))
        if not channel_id or start is None or stop is None:
            continue
        title = _text(prog.find("title")) or "Untitled"
        subtitle = _text(prog.find("sub-title"))
        desc = _text(prog.find("desc"))
        cats = [t for c in prog.findall("category") if (t := _text(c))]
        icon_el = prog.find("icon")
        icon = icon_el.get("src") if icon_el is not None else None
        programmes.append(
            Programme(
                channel_id=channel_id,
                start=start,
                stop=stop,
                title=title,
                subtitle=subtitle,
                description=desc,
                categories=cats,
                icon=icon,
            )
        )
    logger.info("Parsed %d XMLTV programmes across %d channels", len(programmes), len(channel_names))
    return channel_names, programmes
