export type Channel = {
  id: string;
  number?: string | null;
  name: string;
  logo?: string | null;
  group?: string | null;
  url: string;
  station_id?: string | null;
  source?: string;
};

export type Programme = {
  channel_id: string;
  start: number;
  stop: number;
  title: string;
  subtitle?: string | null;
  description?: string | null;
  categories?: string[];
  icon?: string | null;
};

export type CecCapabilities = {
  power: boolean;
  volume: boolean;
  mute: boolean;
  method: string;
};

export type Device = {
  id: string;
  name: string;
  host: string;
  port: number;
  token?: string;
  online: boolean;
  last_seen?: number | null;
  model?: string | null;
  manufacturer?: string | null;
  android_version?: string | null;
  capabilities: {
    multiview_max: number;
    layouts: string[];
    cec: CecCapabilities;
    mpeg_ts: boolean;
    hls: boolean;
    weak_decoder?: boolean;
    chip_family?: string;
    chip_note?: string;
  };
};

export type SessionSlot = {
  channel_id?: string | null;
  url?: string | null;
  title?: string | null;
  audio?: boolean;
  youtube_url?: string | null;
  apituner_channel?: string | null;
};

export type Session = {
  id: string;
  device_id: string;
  mode: "single" | "multiview";
  layout: "1" | "2x1" | "1x2" | "2x2" | "3x3";
  slots: SessionSlot[];
  status: string;
  error?: string | null;
};

export type AppConfig = {
  channels_dvr_m3u_url: string;
  channels_dvr_xmltv_url: string;
  m3u_refresh_seconds: number;
  xmltv_refresh_seconds: number;
  client_auth_token: string;
  apituner_base_url: string;
  apituner_auth_token: string;
  server_port: number;
};

export type Status = {
  version: string;
  channels: number;
  programmes: number;
  channels_updated_at: number;
  epg_updated_at: number;
  last_error?: string | null;
  devices_online: number;
  devices_total: number;
  apituner_configured: boolean;
  now: number;
};

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
  });
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      detail = body.detail || JSON.stringify(body);
    } catch {
      /* ignore */
    }
    throw new Error(detail);
  }
  if (res.status === 204) return undefined as T;
  return res.json();
}

export const api = {
  status: () => req<Status>("/api/status"),
  channels: () => req<Channel[]>("/api/channels"),
  epg: (from: number, to: number) =>
    req<Programme[]>(`/api/epg?from=${from}&to=${to}`),
  devices: () => req<Device[]>("/api/devices"),
  createDevice: (body: {
    name: string;
    host: string;
    port?: number;
    token?: string;
    platform?: "android" | "tvos";
  }) => req<Device>("/api/devices", { method: "POST", body: JSON.stringify(body) }),
  updateDevice: (
    id: string,
    body: { name?: string; host?: string; port?: number; token?: string },
  ) => req<Device>(`/api/devices/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
  deleteDevice: (id: string) => req<{ ok: boolean }>(`/api/devices/${id}`, { method: "DELETE" }),
  cec: async (id: string, action: string) => {
    const body = await req<{ success?: boolean; message?: string }>(
      `/api/devices/${id}/cec`,
      { method: "POST", body: JSON.stringify({ action }) },
    );
    if (body?.success === false) {
      throw new Error(body.message || "That control did not succeed");
    }
    return body;
  },
  pairStatus: (id: string) =>
    req<{ requires_pairing: boolean; paired: boolean; has_certs: boolean; method: string }>(
      `/api/devices/${id}/pair/status`,
    ),
  pairStart: (id: string) =>
    req<{ ok: boolean; message?: string }>(`/api/devices/${id}/pair/start`, {
      method: "POST",
      body: "{}",
    }),
  pairFinish: (id: string, pin: string) =>
    req<{ ok: boolean; paired: boolean }>(`/api/devices/${id}/pair/finish`, {
      method: "POST",
      body: JSON.stringify({ pin }),
    }),
  launch: (id: string) =>
    req<{ ok: boolean; online: boolean }>(`/api/devices/${id}/launch`, {
      method: "POST",
      body: "{}",
    }),
  sessions: () => req<Session[]>("/api/sessions"),
  createSession: (body: {
    device_id: string;
    mode: "single" | "multiview";
    layout: string;
    slots: SessionSlot[];
  }) => req<Session>("/api/sessions", { method: "POST", body: JSON.stringify(body) }),
  stopSession: (id: string) =>
    req<Session>(`/api/sessions/${id}/stop`, { method: "POST", body: "{}" }),
  refreshSessionAudio: (id: string) => req<Session>(`/api/sessions/${id}/audio`),
  setSessionAudio: (id: string, index: number) =>
    req<Session>(`/api/sessions/${id}/audio`, {
      method: "POST",
      body: JSON.stringify({ index }),
    }),
  config: () => req<AppConfig>("/api/config"),
  saveConfig: (body: Partial<AppConfig>) =>
    req<AppConfig>("/api/config", { method: "PUT", body: JSON.stringify(body) }),
  refresh: () => req("/api/refresh", { method: "POST" }),
  resolveYoutube: (youtube_url: string, title?: string) =>
    req<SessionSlot>("/api/youtube/resolve", {
      method: "POST",
      body: JSON.stringify({ youtube_url, title }),
    }),
  apitunerStatus: () => req<{ enabled: boolean; error?: string }>("/api/apituner/status"),
};

/** Placeholder returned when the server redacts a stored secret. */
export const REDACTED_SECRET = "••••••••";

