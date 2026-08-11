# TVMaestro Apple TV client

Full-featured tvOS app that speaks the same LAN control protocol as the Android client, so the TVMaestro web UI can tune, multiview, and adjust volume on Apple TV.

## Features

- Control API on port **9093** (configurable): health, info, session start/stop, CEC volume/mute
- Multiview layouts `1`, `2x1`, `1x2`, `2x2` with empty-pane placeholders and single audio focus
- `AVPlayer` grid with staggered start, per-pane errors, title overlays, Now Playing metadata
- In-app volume gain / mute from the web UI (`player_gain` — tvOS cannot inject HDMI volume keys)
- Idle-timer disabled while playing; auto-hiding chrome; Menu remote stops the session
- Branded idle screen with LAN IP registration hints
- Optional auth token; MPEG-TS → HLS rewrite when Channels DVR query params allow it

## Requirements

- Xcode 15+ (tvOS 17 SDK)
- Apple TV on the same LAN as the TVMaestro server
- Leave the app **open** (tvOS has no Android-style boot foreground service)

## Build & run

```bash
# Automated (CI / local with Xcode installed)
scripts/build-appletv.sh

# Or open in Xcode
open appletv/TVMaestro.xcodeproj
```

`scripts/build-all.sh` includes the Apple TV step when full Xcode is available. GitHub Actions builds the tvOS Simulator app on `macos-15` and uploads the `.app` artifact.

### Device install

1. Select the **TVMaestro** scheme and your Apple TV (or simulator).
2. Set your **Team** under Signing & Capabilities for device installs.
3. Run. Allow **Local Network** when prompted.
4. Register the IP shown on the idle screen in the web UI (**+ Device**, port `9093`).

## Control API

| Method | Path | Body |
|--------|------|------|
| GET | `/api/health` | |
| GET | `/api/info` | `platform: tvos`, capabilities, CEC flags |
| POST | `/api/session` | `{ id, mode, layout, slots:[{url,title,audio,channel_id}] }` |
| GET | `/api/session` | current session |
| POST | `/api/session/stop` | |
| POST | `/api/cec` | `volume_up` / `volume_down` / `mute` (power returns `success: false`) |

Optional header: `X-Auth-Token`.

## Channels DVR

Prefer HLS playlists (`format=hls`). Raw MPEG-TS is unreliable on `AVPlayer`. The client rewrites `format=ts` → `format=hls` when that query param is present and warns otherwise.

## Platform limits

| Capability | Status |
|------------|--------|
| Playback + multiview | Yes |
| Volume / mute from web UI | In-app gain on audio-focus pane |
| TV HDMI volume via Siri Remote | System / CEC (outside this app) |
| Wake / Sleep | Not available — use Siri Remote or Apple TV HDMI-CEC settings |
| Always-on after reboot | Keep app running / re-open after reboot |

## Version

0.2.0
