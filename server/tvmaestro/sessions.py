"""Session orchestration — resolve slots and push to Android / Apple TV clients."""

from __future__ import annotations

import logging
import time
import uuid
from typing import Optional

from . import client_proxy
from .apituner import ApiTunerClient, ApiTunerError
from .devices import DeviceRegistry
from .guide import GuideStore
from .models import Layout, SessionCreate, SessionSlot, SessionState

logger = logging.getLogger(__name__)

LAYOUT_CAPACITY = {
    Layout.one: 1,
    Layout.two_h: 2,
    Layout.two_v: 2,
    Layout.quad: 4,
    Layout.grid3: 9,
}


def _slot_playable(slot: SessionSlot) -> bool:
    return bool(slot.url or slot.channel_id or slot.youtube_url or slot.apituner_channel)


def _audio_index_from_device(payload: object, session: SessionState) -> Optional[int]:
    """Index of the audible pane reported by the TV, if it still matches this session."""
    if not isinstance(payload, dict):
        return None
    live = payload.get("session")
    if not isinstance(live, dict):
        return None
    live_id = live.get("id")
    if live_id and live_id != session.id:
        return None
    live_slots = live.get("slots")
    if not isinstance(live_slots, list):
        return None
    for i, slot in enumerate(live_slots):
        if not isinstance(slot, dict) or not slot.get("audio"):
            continue
        if i < len(session.slots) and _slot_playable(session.slots[i]):
            return i
    return None


def _with_single_audio(slots: list[SessionSlot]) -> list[SessionSlot]:
    """Exactly one audio focus on a playable slot; empty panes stay silent."""
    focus = next((i for i, s in enumerate(slots) if s.audio and _slot_playable(s)), None)
    if focus is None:
        focus = next((i for i, s in enumerate(slots) if _slot_playable(s)), None)
    if focus is None:
        return slots
    return [
        s.model_copy(update={"audio": i == focus and _slot_playable(s)})
        for i, s in enumerate(slots)
    ]


class SessionManager:
    def __init__(
        self,
        devices: DeviceRegistry,
        guide: GuideStore,
        apituner: ApiTunerClient,
    ) -> None:
        self.devices = devices
        self.guide = guide
        self.apituner = apituner
        self._sessions: dict[str, SessionState] = {}
        self._by_device: dict[str, str] = {}

    def list(self) -> list[SessionState]:
        return list(self._sessions.values())

    def get(self, session_id: str) -> Optional[SessionState]:
        return self._sessions.get(session_id)

    def for_device(self, device_id: str) -> Optional[SessionState]:
        sid = self._by_device.get(device_id)
        return self._sessions.get(sid) if sid else None

    async def create(self, body: SessionCreate) -> SessionState:
        device = self.devices.get(body.device_id)
        if not device:
            raise ValueError("Unknown device")

        capacity = LAYOUT_CAPACITY.get(body.layout, 1)
        if body.mode == "single":
            body = body.model_copy(update={"layout": Layout.one})
            capacity = 1

        device_max = max(1, int(device.capabilities.multiview_max or 1))
        if len(body.slots) > device_max:
            note = device.capabilities.chip_note or device.capabilities.chip_family
            raise ValueError(
                f"Device supports at most {device_max} simultaneous stream(s)"
                + (f" ({note})" if note else "")
            )
        if capacity > device_max:
            # Clamp layout to what the SoC can handle
            if device_max == 1:
                body = body.model_copy(update={"layout": Layout.one, "mode": "single"})
                capacity = 1
            elif device_max == 2 and body.layout == Layout.quad:
                body = body.model_copy(update={"layout": Layout.two_h})
                capacity = 2

        if not body.slots:
            raise ValueError("At least one slot is required")
        if len(body.slots) > capacity:
            raise ValueError(f"Layout {body.layout} supports at most {capacity} slots")

        resolved: list[SessionSlot] = []
        for slot in body.slots[:capacity]:
            resolved.append(await self._resolve_slot(slot))

        if not any(_slot_playable(s) for s in resolved):
            raise ValueError("At least one non-empty slot is required")
        resolved = _with_single_audio(resolved)

        now = time.time()
        session = SessionState(
            id=str(uuid.uuid4()),
            device_id=body.device_id,
            mode=body.mode if capacity > 1 else "single",
            layout=body.layout if capacity > 1 else Layout.one,
            slots=resolved,
            status="pending",
            created_at=now,
            updated_at=now,
        )

        # Keep prior session active until the new push succeeds (device still playing it).
        prior = self.for_device(device.id)
        self._sessions[session.id] = session

        try:
            await client_proxy.push_session(device, session)
            session.status = "playing"
            session.updated_at = time.time()
            if prior and prior.id != session.id:
                prior.status = "stopped"
                prior.updated_at = session.updated_at
                self._sessions[prior.id] = prior
            self._by_device[device.id] = session.id
            self._sessions[session.id] = session
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to push session to %s", device.id)
            session.status = "error"
            session.error = str(exc)
            session.updated_at = time.time()
            # Do not keep failed attempts in the session list (UI would hide the
            # session that is still playing on the device).
            self._sessions.pop(session.id, None)
        return session

    async def stop(self, session_id: str) -> Optional[SessionState]:
        session = self._sessions.get(session_id)
        if not session:
            return None
        device = self.devices.get(session.device_id)
        if device:
            try:
                await client_proxy.stop_session(device)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Stop on device failed: %s", exc)
        session.status = "stopped"
        session.updated_at = time.time()
        self._sessions[session_id] = session
        if self._by_device.get(session.device_id) == session_id:
            del self._by_device[session.device_id]
        return session

    async def refresh_audio(self, session_id: str) -> Optional[SessionState]:
        """Read the device's current audible pane so a remote swipe matches the guide."""
        session = self._sessions.get(session_id)
        if not session or session.status != "playing":
            return session
        device = self.devices.get(session.device_id)
        if not device:
            return session
        try:
            payload = await client_proxy.get_session(device)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Audio refresh failed for %s: %s", session_id, exc)
            return session
        focus = _audio_index_from_device(payload, session)
        if focus is None:
            return session
        return self._store_audio(session, focus)

    async def set_audio(self, session_id: str, index: int) -> SessionState:
        session = self._sessions.get(session_id)
        if not session:
            raise KeyError(session_id)
        if session.status != "playing":
            raise ValueError("Session is not playing")
        if index < 0 or index >= len(session.slots) or not _slot_playable(session.slots[index]):
            raise ValueError("No playable slot at that index")
        device = self.devices.get(session.device_id)
        if not device:
            raise ValueError("Unknown device")
        await client_proxy.set_audio(device, index)
        return self._store_audio(session, index)

    def _store_audio(self, session: SessionState, index: int) -> SessionState:
        slots = [
            slot.model_copy(update={"audio": i == index and _slot_playable(slot)})
            for i, slot in enumerate(session.slots)
        ]
        updated = session.model_copy(update={"slots": slots, "updated_at": time.time()})
        self._sessions[session.id] = updated
        return updated

    async def stop_device(self, device_id: str) -> Optional[SessionState]:
        sid = self._by_device.get(device_id)
        if not sid:
            return None
        return await self.stop(sid)

    async def _resolve_slot(self, slot: SessionSlot) -> SessionSlot:
        if slot.youtube_url or slot.apituner_channel:
            try:
                resolved = await self.apituner.resolve_youtube_slot(
                    slot.youtube_url or "",
                    title=slot.title,
                    channel_hint=slot.apituner_channel,
                )
                return resolved.model_copy(update={"audio": slot.audio})
            except ApiTunerError:
                if slot.url:
                    return slot
                raise

        if slot.url:
            return slot

        if not slot.channel_id:
            # Empty pane placeholder (preserves multiview grid position).
            return slot.model_copy(update={"url": None, "audio": False})

        ch = self.guide.get_channel(slot.channel_id)
        if not ch:
            raise ValueError(f"Unknown channel_id: {slot.channel_id}")
        return slot.model_copy(update={"url": ch.url, "title": slot.title or ch.name})
