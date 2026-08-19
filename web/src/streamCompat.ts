import type { Channel, Device } from "./api";

/** True when a Channels DVR / M3U URL is likely raw MPEG-TS (not HLS). */
export function looksLikeMpegTs(url: string): boolean {
  const u = url.toLowerCase();
  if (u.includes(".m3u8")) return false;
  if (u.includes("format=hls")) return false;
  if (u.includes("format=ts") || u.includes("format=mpegts")) return true;
  if (u.includes("codec=copy") && !u.includes("format=hls")) return true;
  try {
    const path = new URL(url).pathname.toLowerCase();
    if (path.endsWith(".ts")) return true;
  } catch {
    /* ignore invalid URL */
  }
  return false;
}

export function devicePrefersHls(device: Device | null | undefined): boolean {
  return device?.capabilities?.mpeg_ts === false;
}

export function isAppleTvDevice(device: Device | null | undefined): boolean {
  const family = device?.capabilities?.chip_family?.toLowerCase() ?? "";
  const note = device?.capabilities?.chip_note?.toLowerCase() ?? "";
  const mfg = device?.manufacturer?.toLowerCase() ?? "";
  return family === "apple" || mfg === "apple" || note.includes("avplayer");
}

/** User-facing warning when tuning MPEG-TS to an HLS-first client (e.g. Apple TV). */
export function streamCompatWarning(
  device: Device | null | undefined,
  channel: Channel,
): string | null {
  if (!device || !looksLikeMpegTs(channel.url)) return null;
  if (!devicePrefersHls(device)) return null;
  const label = isAppleTvDevice(device) ? "Apple TV" : device.name;
  return `${label} prefers HLS. This channel URL looks like MPEG-TS and may not play. In Channels DVR, use format=hls in your M3U URL.`;
}

export function youtubeCompatWarning(device: Device | null | undefined): string | null {
  if (!device || !devicePrefersHls(device)) return null;
  const label = isAppleTvDevice(device) ? "Apple TV" : device.name;
  return `${label} prefers HLS. APITuner YouTube streams are MPEG-TS and often will not play. Tune a Channels HLS channel instead, or play YouTube on Android TV.`;
}

export function multiviewStreamWarnings(
  device: Device | null | undefined,
  channels: Array<Channel | null>,
): string[] {
  const out: string[] = [];
  for (const ch of channels) {
    if (!ch) continue;
    const w = streamCompatWarning(device, ch);
    if (w && !out.includes(w)) out.push(w);
  }
  return out;
}
