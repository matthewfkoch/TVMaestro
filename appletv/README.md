# TVMaestro Apple TV client

tvOS app that speaks the same LAN control protocol as the Android client, so the TVMaestro web UI can tune and multiview on Apple TV.

## Requirements

- Xcode 15+ (tvOS 17 SDK)
- Apple TV on the same LAN as the TVMaestro server
- **HLS** stream URLs from Channels DVR (raw MPEG-TS is unreliable on `AVPlayer`)

## Build & run

```bash
open appletv/TVMaestro.xcodeproj
```

1. Select the **TVMaestro** scheme and your Apple TV (or simulator).
2. Set your **Team** under Signing & Capabilities if deploying to a device.
3. Run. Allow **Local Network** when prompted.
4. Note the IP shown on the idle screen (control port defaults to **9093**).
5. In the web UI: **+ Device** → Apple TV LAN IP → port `9093`.

Optional: set a matching auth token in **Settings** on the Apple TV and on the device row in the web UI.

## Control API

Same contract as Android:

| Method | Path | Body |
|--------|------|------|
| GET | `/api/health` | |
| GET | `/api/info` | capabilities (`platform: tvos`, `hls: true`, `mpeg_ts: false`) |
| POST | `/api/session` | `{ id, mode, layout, slots:[{url,title,audio,channel_id}] }` |
| GET | `/api/session` | current session |
| POST | `/api/session/stop` | |
| POST | `/api/cec` | volume/mute acknowledged; power not supported on tvOS |

## Multiview

Layouts `1`, `2x1`, `1x2`, `2x2` — one `AVPlayer` per playable slot; empty panes keep grid position; exactly one audio-focus slot.

## Channels DVR tip

Prefer an HLS playlist in your M3U (or a per-tune HLS URL) rather than `format=ts`. The client advertises `mpeg_ts: false` so the server/UI can treat Apple TV accordingly.

## Limits (v0.1)

- No TV wake/sleep via this app (use the Siri Remote / system HDMI-CEC).
- No custom app icon / top shelf art yet.
- Not built in CI (needs macOS + Xcode).
