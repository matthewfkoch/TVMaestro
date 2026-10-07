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

## Install options

| Method | Best for |
|--------|----------|
| **TestFlight** | Your Apple TV — same Apple account as Big Stick Invitational |
| **Xcode Run** | Active development / debugging |
| **Simulator** | UI smoke test only (not on a real TV) |

## TestFlight

Same Apple Developer account as **Big Stick Invitational**. BSI uses `eas build --auto-submit` for iPhone; TVMaestro uses Fastlane for native tvOS.

```bash
export FASTLANE_USER=your@email.com
export APPLE_TEAM_ID=XXXXXXXXXX
scripts/testflight-appletv.sh
```

Full setup (App Store Connect app, `testflight.json` → `ascAppId`): **`docs/TESTFLIGHT.md`**

## Xcode direct install

```bash
open appletv/TVMaestro.xcodeproj
```

Pair the Apple TV in **Window → Devices and Simulators**, set your Team under Signing, select the TV as destination, and **Run** (⌘R).

Simulator-only build: `scripts/build-appletv.sh`

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

Prefer HLS playlists (`format=hls`). Raw MPEG-TS is unreliable on `AVPlayer`. The web UI warns when tuning MPEG-TS to Apple TV.

## Platform limits

| Capability | Status |
|------------|--------|
| Playback + multiview | Yes |
| Volume / mute from web UI | In-app gain on audio-focus pane |
| Wake / Sleep | Not available |
| Always-on after reboot | Re-open app (or launch from TestFlight) |

## Version

0.3.0
