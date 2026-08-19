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
| **TestFlight** | Your Apple TV at home — no weekly Xcode reinstall |
| **Xcode Run** | Active development / debugging |
| **Simulator** | UI smoke test only (not on a real TV) |

## TestFlight

### One-time App Store Connect setup

1. Register bundle ID **`com.tvmaestro.client`** (Apple TV) in the [Developer portal](https://developer.apple.com/account/resources/identifiers/list).
2. **App Store Connect → Apps → +** → New App → platform **tvOS**, bundle ID above.
3. **Users and Access → Integrations → App Store Connect API** → create key → download `.p8`.

### GitHub Actions (automated)

Add repository secrets:

| Secret | Description |
|--------|-------------|
| `APPLE_TEAM_ID` | 10-char Team ID |
| `ASC_KEY_ID` | API key ID |
| `ASC_ISSUER_ID` | Issuer UUID |
| `ASC_PRIVATE_KEY` | Contents of `AuthKey_*.p8` |

Then either:

- Push a tag: `git tag v0.2.1 && git push origin v0.2.1` (runs **TestFlight (Apple TV)** workflow), or
- **Actions → TestFlight (Apple TV) → Run workflow**

### Local upload

```bash
export APPLE_TEAM_ID=XXXXXXXXXX
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_API_KEY_PATH=$HOME/.appstoreconnect/AuthKey_XXXXXX.p8
scripts/testflight-appletv.sh
```

Or from `appletv/` after `bundle install`:

```bash
bundle exec fastlane beta   # upload
bundle exec fastlane build  # IPA only, no upload
```

### On the Apple TV

1. Install **TestFlight** from the tvOS App Store.
2. Open TestFlight → **TVMaestro** → Install (internal testing — add your Apple ID under App Store Connect → TestFlight → Internal Testing if needed).
3. Launch TVMaestro, allow **Local Network**.
4. In the web UI: **+ Device** → Apple TV LAN IP → port **9093**.

## Xcode direct install

```bash
open appletv/TVMaestro.xcodeproj
```

1. **Signing & Capabilities** → your Team.
2. Pair Apple TV (**Window → Devices and Simulators**).
3. Select the TV as destination → **Run** (⌘R).

Simulator-only build:

```bash
scripts/build-appletv.sh
```

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

Prefer HLS playlists (`format=hls`). Raw MPEG-TS is unreliable on `AVPlayer`. The client rewrites `format=ts` → `format=hls` when that query param is present; the web UI warns when tuning MPEG-TS to Apple TV.

## Platform limits

| Capability | Status |
|------------|--------|
| Playback + multiview | Yes |
| Volume / mute from web UI | In-app gain on audio-focus pane |
| TV HDMI volume via Siri Remote | System / CEC (outside this app) |
| Wake / Sleep | Not available — use Siri Remote or Apple TV HDMI-CEC settings |
| Always-on after reboot | Re-open app (or launch from TestFlight) |

## Version

0.2.0
