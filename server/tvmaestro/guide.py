"""Fetch and cache Channels DVR M3U + XMLTV."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path
from typing import Optional

import httpx

from .config import ConfigStore, data_dir
from .m3u import parse_m3u
from .models import Channel, Programme
from .xmltv import parse_xmltv

logger = logging.getLogger(__name__)


class GuideStore:
    def __init__(self, store: ConfigStore) -> None:
        self.store = store
        self.channels: list[Channel] = []
        self.programmes: list[Programme] = []
        self.xmltv_names: dict[str, str] = {}
        self.channels_updated_at: float = 0.0
        self.epg_updated_at: float = 0.0
        self.last_error: Optional[str] = None
        self._lock = asyncio.Lock()
        self._task: asyncio.Task | None = None
        self._cache_dir = data_dir() / "cache"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._load_disk_cache()

    def _channels_path(self) -> Path:
        return self._cache_dir / "channels.json"

    def _epg_path(self) -> Path:
        return self._cache_dir / "epg.json"

    def _load_disk_cache(self) -> None:
        try:
            cp = self._channels_path()
            if cp.exists():
                raw = json.loads(cp.read_text(encoding="utf-8"))
                self.channels = [Channel.model_validate(c) for c in raw.get("channels", [])]
                self.channels_updated_at = float(raw.get("updated_at") or 0)
            ep = self._epg_path()
            if ep.exists():
                raw = json.loads(ep.read_text(encoding="utf-8"))
                self.programmes = [Programme.model_validate(p) for p in raw.get("programmes", [])]
                self.xmltv_names = dict(raw.get("xmltv_names") or {})
                self.epg_updated_at = float(raw.get("updated_at") or 0)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Disk cache load failed: %s", exc)

    def _save_channels(self) -> None:
        payload = {
            "updated_at": self.channels_updated_at,
            "channels": [c.model_dump() for c in self.channels],
        }
        self._channels_path().write_text(json.dumps(payload), encoding="utf-8")

    def _save_epg(self) -> None:
        payload = {
            "updated_at": self.epg_updated_at,
            "xmltv_names": self.xmltv_names,
            "programmes": [p.model_dump() for p in self.programmes],
        }
        self._epg_path().write_text(json.dumps(payload), encoding="utf-8")

    async def start(self) -> None:
        try:
            await self.refresh()
        except Exception as exc:  # noqa: BLE001
            self.last_error = str(exc)
            logger.exception(
                "Initial guide refresh failed; serving disk cache if available"
            )
        self._task = asyncio.create_task(self._loop(), name="guide-refresh")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _loop(self) -> None:
        while True:
            cfg = self.store.config
            await asyncio.sleep(min(cfg.m3u_refresh_seconds, cfg.xmltv_refresh_seconds, 60))
            try:
                now = time.time()
                if now - self.channels_updated_at >= cfg.m3u_refresh_seconds:
                    await self.refresh_channels()
                if now - self.epg_updated_at >= cfg.xmltv_refresh_seconds:
                    await self.refresh_epg()
            except Exception as exc:  # noqa: BLE001
                self.last_error = str(exc)
                logger.exception("Guide refresh failed")

    async def refresh(self) -> None:
        async with self._lock:
            await self._refresh_channels()
            await self._refresh_epg()

    async def refresh_channels(self) -> None:
        async with self._lock:
            await self._refresh_channels()

    async def refresh_epg(self) -> None:
        async with self._lock:
            await self._refresh_epg()

    async def _refresh_channels(self) -> None:
        url = self.store.config.channels_dvr_m3u_url.strip()
        if not url:
            logger.debug("Channels DVR M3U URL is not configured; skipping refresh")
            return
        logger.info("Fetching M3U %s", url)
        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0, connect=10.0)) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            text = resp.text
        channels = parse_m3u(text)
        self.channels = channels
        self.channels_updated_at = time.time()
        self._save_channels()
        self.last_error = None

    async def _refresh_epg(self) -> None:
        url = self.store.config.channels_dvr_xmltv_url.strip()
        if not url:
            logger.debug("Channels DVR XMLTV URL is not configured; skipping refresh")
            return
        logger.info("Fetching XMLTV %s", url)
        async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=10.0)) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            text = resp.text
        names, programmes = parse_xmltv(text)
        self.xmltv_names = names
        self.programmes = programmes
        self.epg_updated_at = time.time()
        self._save_epg()
        self.last_error = None
        self._remap_channel_ids()

    def _remap_channel_ids(self) -> None:
        """Align programme channel_id with M3U channel ids when possible."""
        by_station = {c.station_id: c.id for c in self.channels if c.station_id}
        by_name = {c.name.lower(): c.id for c in self.channels}
        mapped: list[Programme] = []
        for p in self.programmes:
            new_id = by_station.get(p.channel_id)
            if not new_id:
                display = self.xmltv_names.get(p.channel_id, "").lower()
                new_id = by_name.get(display) if display else None
            if not new_id:
                new_id = by_name.get(p.channel_id.lower())
            if new_id and new_id != p.channel_id:
                mapped.append(p.model_copy(update={"channel_id": new_id}))
            else:
                mapped.append(p)
        self.programmes = mapped

    def get_channel(self, channel_id: str) -> Optional[Channel]:
        for c in self.channels:
            if c.id == channel_id:
                return c
        return None

    def epg(
        self,
        *,
        from_ts: Optional[int] = None,
        to_ts: Optional[int] = None,
        channel_ids: Optional[set[str]] = None,
    ) -> list[Programme]:
        now = int(time.time())
        start = from_ts if from_ts is not None else now - 3600
        end = to_ts if to_ts is not None else now + 6 * 3600
        out: list[Programme] = []
        for p in self.programmes:
            if channel_ids and p.channel_id not in channel_ids:
                continue
            if p.stop <= start or p.start >= end:
                continue
            out.append(p)
        out.sort(key=lambda x: (x.channel_id, x.start))
        return out
