"""Pydantic models for TVMaestro config, guide, devices, and sessions."""

from __future__ import annotations

from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class AppConfig(BaseModel):
    channels_dvr_m3u_url: str = ""
    channels_dvr_xmltv_url: str = ""
    m3u_refresh_seconds: int = 300
    xmltv_refresh_seconds: int = 900
    # Reserved — not enforced by the API yet. Empty means open LAN control plane.
    client_auth_token: str = ""
    apituner_base_url: str = ""
    apituner_auth_token: str = ""
    # Informational only; listen port comes from uvicorn / compose / TVMAESTRO_PORT.
    server_port: int = 6790


class Channel(BaseModel):
    id: str
    number: Optional[str] = None
    name: str
    logo: Optional[str] = None
    group: Optional[str] = None
    url: str
    station_id: Optional[str] = None
    source: Literal["channels", "apituner", "youtube"] = "channels"


class Programme(BaseModel):
    channel_id: str
    start: int  # unix seconds
    stop: int
    title: str
    subtitle: Optional[str] = None
    description: Optional[str] = None
    categories: list[str] = Field(default_factory=list)
    icon: Optional[str] = None


class CecCapabilities(BaseModel):
    power: bool = False
    volume: bool = True
    mute: bool = True
    method: str = "keys"  # keys | hdmi_api | unavailable


class DeviceCapabilities(BaseModel):
    multiview_max: int = 1
    layouts: list[str] = Field(default_factory=lambda: ["1"])
    cec: CecCapabilities = Field(default_factory=CecCapabilities)
    mpeg_ts: bool = True
    hls: bool = True
    weak_decoder: bool = True
    chip_family: str = "unknown"
    chip_note: str = ""


class Device(BaseModel):
    id: str
    name: str
    host: str
    port: int = 9093
    token: str = ""
    online: bool = False
    last_seen: Optional[float] = None
    model: Optional[str] = None
    manufacturer: Optional[str] = None
    android_version: Optional[str] = None
    capabilities: DeviceCapabilities = Field(default_factory=DeviceCapabilities)
    meta: dict[str, Any] = Field(default_factory=dict)


class DeviceCreate(BaseModel):
    id: Optional[str] = None
    name: str
    host: str
    port: int = 9093
    token: str = ""
    # tvos seeds Apple identity before the app has ever been online, so the
    # guide can pair and launch it. android (or omitted) waits for /api/info.
    platform: Optional[Literal["android", "tvos"]] = None


class DeviceUpdate(BaseModel):
    name: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    token: Optional[str] = None


class Layout(str, Enum):
    one = "1"
    two_h = "2x1"
    two_v = "1x2"
    quad = "2x2"
    grid3 = "3x3"


class SessionSlot(BaseModel):
    channel_id: Optional[str] = None
    url: Optional[str] = None
    title: Optional[str] = None
    audio: bool = False
    # Stretch: resolve via APITuner YouTube / encoder path
    youtube_url: Optional[str] = None
    apituner_channel: Optional[str] = None


class SessionCreate(BaseModel):
    device_id: str
    mode: Literal["single", "multiview"] = "single"
    layout: Layout = Layout.one
    slots: list[SessionSlot]


class SessionState(BaseModel):
    id: str
    device_id: str
    mode: Literal["single", "multiview"]
    layout: Layout
    slots: list[SessionSlot]
    status: Literal["pending", "playing", "error", "stopped"] = "pending"
    error: Optional[str] = None
    created_at: float
    updated_at: float


class CecAction(str, Enum):
    power_on = "power_on"
    power_off = "power_off"
    volume_up = "volume_up"
    volume_down = "volume_down"
    mute = "mute"


class CecRequest(BaseModel):
    action: CecAction


class CecByHostRequest(BaseModel):
    host: str
    action: CecAction


class PairFinishRequest(BaseModel):
    pin: str


class ConfigUpdate(BaseModel):
    channels_dvr_m3u_url: Optional[str] = None
    channels_dvr_xmltv_url: Optional[str] = None
    m3u_refresh_seconds: Optional[int] = None
    xmltv_refresh_seconds: Optional[int] = None
    client_auth_token: Optional[str] = None
    apituner_base_url: Optional[str] = None
    apituner_auth_token: Optional[str] = None


class YoutubeTuneRequest(BaseModel):
    """Resolve a YouTube watch URL into a playable MPEG-TS slot via APITuner."""

    youtube_url: str
    title: Optional[str] = None
