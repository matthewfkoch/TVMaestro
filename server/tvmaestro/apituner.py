"""Optional APITuner integration for YouTube → MPEG-TS encoder streams."""

from __future__ import annotations

import logging
from typing import Any, Optional
from urllib.parse import quote, urljoin

import httpx

from .config import ConfigStore
from .models import Channel, SessionSlot

logger = logging.getLogger(__name__)


class ApiTunerError(Exception):
    pass


class ApiTunerClient:
    def __init__(self, store: ConfigStore) -> None:
        self.store = store

    @property
    def enabled(self) -> bool:
        return bool(self.store.config.apituner_base_url.strip())

    def _headers(self) -> dict[str, str]:
        h = {"Accept": "application/json"}
        token = self.store.config.apituner_auth_token.strip()
        if token:
            h["X-Auth-Token"] = token
            h["Authorization"] = f"Bearer {token}"
        return h

    def _base(self) -> str:
        return self.store.config.apituner_base_url.rstrip("/") + "/"

    async def status(self) -> dict[str, Any]:
        if not self.enabled:
            return {"enabled": False}
        url = urljoin(self._base(), "api/status")
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers=self._headers())
            if resp.status_code == 404:
                # Fallback probe
                resp = await client.get(urljoin(self._base(), "channels.m3u"), headers=self._headers())
                resp.raise_for_status()
                return {"enabled": True, "reachable": True, "detail": "m3u_ok"}
            resp.raise_for_status()
            data = resp.json()
            data["enabled"] = True
            return data

    async def resolve_youtube_slot(
        self,
        youtube_url: str,
        *,
        title: Optional[str] = None,
        channel_hint: Optional[str] = None,
    ) -> SessionSlot:
        """
        Resolve a YouTube watch URL into a playable TS URL via APITuner.

        Strategy:
        1. If APITuner exposes a tune/launch helper, prefer that.
        2. Else look up M3U entries matching the YouTube deep link / channel hint
           and return that stream URL (encoder relay already configured in APITuner).
        """
        if not self.enabled:
            raise ApiTunerError("APITuner base URL is not configured")

        base = self._base()
        headers = self._headers()

        # Attempt management tune endpoint if present (best-effort; may 404).
        async with httpx.AsyncClient(timeout=30.0) as client:
            for path in ("api/tune", "api/youtube", "api/launch"):
                try:
                    resp = await client.post(
                        urljoin(base, path),
                        headers=headers,
                        json={"url": youtube_url, "youtube_url": youtube_url, "title": title},
                    )
                    if resp.status_code < 400:
                        data = resp.json()
                        stream = data.get("stream_url") or data.get("url") or data.get("mpegts")
                        if stream:
                            return SessionSlot(
                                url=stream,
                                title=title or data.get("title") or "YouTube",
                                youtube_url=youtube_url,
                                audio=True,
                            )
                except Exception:  # noqa: BLE001
                    continue

            # Fallback: fetch M3U and match by URL fragment or channel hint
            m3u_resp = await client.get(urljoin(base, "channels.m3u"), headers=headers)
            m3u_resp.raise_for_status()
            from .m3u import parse_m3u

            channels = parse_m3u(m3u_resp.text, source="apituner")
            match = _match_channel(channels, youtube_url, channel_hint)
            if not match:
                raise ApiTunerError(
                    "No APITuner channel matched this YouTube URL. "
                    "Configure a YouTube TV channel in APITuner or set apituner_channel."
                )

            # Preferred stream path through APITuner proxy
            stream_url = match.url
            # If channel has a number, prefer /stream/{number} for encoder relay
            if match.number:
                stream_url = urljoin(base, f"stream/{quote(str(match.number))}")

            return SessionSlot(
                url=stream_url,
                title=title or match.name,
                channel_id=match.id,
                youtube_url=youtube_url,
                apituner_channel=match.number or match.id,
                audio=True,
            )


def _match_channel(
    channels: list[Channel],
    youtube_url: str,
    channel_hint: Optional[str],
) -> Optional[Channel]:
    yt = youtube_url.lower()
    hint = (channel_hint or "").lower()
    for ch in channels:
        hay = " ".join(
            filter(
                None,
                [ch.id, ch.name, ch.url, ch.number or "", ch.group or ""],
            )
        ).lower()
        if hint and hint in hay:
            return ch
        if "youtube" in hay and ("youtube" in yt or "youtu.be" in yt):
            return ch
        if yt and yt in ch.url.lower():
            return ch
    # Last resort: first YouTube-looking channel
    for ch in channels:
        if "youtube" in ch.name.lower() or "youtube" in (ch.group or "").lower():
            return ch
    return None
