# TVMaestro Apple TV client

Full-featured tvOS app that speaks the same LAN control protocol as the Android client, so the TVMaestro web UI can tune, multiview, and adjust volume on Apple TV.

## Features

- Control API on port **9093** (configurable): health, info, session start/stop, CEC volume/mute
- Multiview layouts `1`, `2x1`, `1x2`, `2x2`, `3x3` with empty-pane placeholders and single audio focus
- KSPlayer grid with staggered start, per-pane errors, title chips, and Now Playing metadata
- Volume and mute from the guide use the same Companion presses as the Siri Remote (pair the Apple TV first)
- Idle-timer disabled while playing; auto-hiding chrome; Menu remote stops the session
- Branded idle screen with LAN IP registration hints
- Optional auth token

## Requirements

- Xcode 15+ (tvOS 17 SDK)
- Apple TV on the same LAN as the TVMaestro server
- Leave the app **open**, or pair the Apple TV in the web UI so Tune / **Open** can wake the Apple TV and launch the app

## Install options

| Method | Best for |
|--------|----------|
| **TestFlight** | Install on an Apple TV without a Mac cable |
| **Xcode Run** | Active development / debugging |
| **Simulator** | UI smoke test only (not on a real TV) |

## TestFlight

TVMaestro is a native tvOS app, so TestFlight uploads go through Fastlane.

```bash
export FASTLANE_USER=your@email.com
export APPLE_TEAM_ID=XXXXXXXXXX
scripts/testflight-appletv.sh
```

Full setup (App Store Connect app, `testflight.json` → `ascAppId`): **`docs/TESTFLIGHT.md`**

App Store listing text is in `fastlane/metadata`. It is not submitted. See **`docs/APP_STORE.md`**.

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

The app plays the original MPEG-TS stream, including MPEG-2, with KSPlayer software decode. An `.m3u8` URL still plays if that is what the guide sends.

## Platform limits

| Capability | Status |
|------------|--------|
| Playback + multiview | Yes |
| Volume / mute from web UI | In-app gain on audio-focus pane |
| Wake / Sleep of the Apple TV | After one Companion pairing (Edit device → Pair). The television follows only if Control TVs and Receivers is on. |
| Open the app from the guide | After the same pairing |

## Version

0.4.1

## License

See the repository [LICENSE](../LICENSE) and [NOTICE](../NOTICE). This app links KSPlayer and FFmpegKit, GPL-3.0-only.
