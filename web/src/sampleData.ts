import type {
  AppConfig,
  Channel,
  Device,
  Programme,
  Session,
  Status,
} from "./api";

const nowSec = () => Math.floor(Date.now() / 1000);

export const SAMPLE_CHANNELS: Channel[] = [
  {
    id: "sample-1",
    number: "1.1",
    name: "Sample News",
    logo: null,
    group: "Sample",
    url: "sample://news",
    station_id: "sample-1",
    source: "sample",
  },
  {
    id: "sample-2",
    number: "2.1",
    name: "Sample Sports",
    logo: null,
    group: "Sample",
    url: "sample://sports",
    station_id: "sample-2",
    source: "sample",
  },
  {
    id: "sample-3",
    number: "3.1",
    name: "Sample Kids",
    logo: null,
    group: "Sample",
    url: "sample://kids",
    station_id: "sample-3",
    source: "sample",
  },
  {
    id: "sample-4",
    number: "4.1",
    name: "Sample Movies",
    logo: null,
    group: "Sample",
    url: "sample://movies",
    station_id: "sample-4",
    source: "sample",
  },
];

export function sampleProgrammes(from: number, to: number): Programme[] {
  const titles: Record<string, string[]> = {
    "sample-1": ["Morning Briefing", "Midday Report", "Evening News"],
    "sample-2": ["Match Preview", "Live Game", "Postgame Show"],
    "sample-3": ["Cartoon Hour", "Learning Time", "Story Circle"],
    "sample-4": ["Classic Feature", "New Release", "Late Screening"],
  };
  const out: Programme[] = [];
  for (const ch of SAMPLE_CHANNELS) {
    const list = titles[ch.id] || ["Sample Program"];
    let start = from - (from % 3600);
    let i = 0;
    while (start < to) {
      const stop = start + 3600;
      out.push({
        channel_id: ch.id,
        start,
        stop,
        title: list[i % list.length],
        subtitle: "Sample guide",
        description:
          "This is a sample listing for App Review. The phone does not play video.",
        categories: ["Sample"],
        icon: null,
      });
      start = stop;
      i += 1;
    }
  }
  return out;
}

export const SAMPLE_DEVICES: Device[] = [
  {
    id: "sample-tv",
    name: "Sample Television",
    host: "192.168.1.50",
    port: 6791,
    online: true,
    last_seen: nowSec(),
    model: "Sample",
    manufacturer: "TVMaestro",
    capabilities: {
      multiview_max: 4,
      layouts: ["1", "2x1", "1x2", "2x2"],
      cec: { power: false, volume: false, mute: false, method: "none" },
      mpeg_ts: true,
      hls: true,
    },
  },
];

export const SAMPLE_SESSIONS: Session[] = [];

export function sampleStatus(): Status {
  return {
    version: "sample",
    channels: SAMPLE_CHANNELS.length,
    programmes: SAMPLE_CHANNELS.length * 12,
    channels_updated_at: nowSec(),
    epg_updated_at: nowSec(),
    last_error: null,
    devices_online: 1,
    devices_total: 1,
    apituner_configured: false,
    now: nowSec(),
  };
}

export const SAMPLE_CONFIG: AppConfig = {
  channels_dvr_m3u_url: "",
  channels_dvr_xmltv_url: "",
  m3u_refresh_seconds: 300,
  xmltv_refresh_seconds: 900,
  client_auth_token: "",
  apituner_base_url: "",
  apituner_auth_token: "",
  server_port: 6790,
};

export function isSampleMode(): boolean {
  return typeof window !== "undefined" && Boolean(window.__TVMAESTRO_SAMPLE__);
}
