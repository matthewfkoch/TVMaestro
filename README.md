# TVMaestro

<img src="branding/logo-app-icon-512.png" alt="TVMaestro" width="96" height="96" />

EPG orchestrator for [Channels DVR](https://getchannels.com/) with a polished web guide and an Android TV client that plays streams (including up to 4-way multiview). Optional YouTube/encoder path via [APITuner](https://github.com/matthewfkoch/APITuner).

## Architecture

- **Server** (Python / FastAPI, port **6790**) — ingests Channels DVR M3U + XMLTV, device registry, session orchestration
- **Web UI** (React / Vite) — broadcast-style EPG, tune sheet, multiview composer, CEC controls
- **Android client** (Kotlin / Media3 ExoPlayer, control API **9093**) — plays HLS/MPEG-TS; best-effort HDMI-CEC
- **Apple TV** (`appletv/`) — tvOS client (same control API as Android; prefer HLS streams)

Control plane: browser → TVMaestro server → Android device.  
Media plane: Android device pulls stream URLs directly from Channels (or APITuner).

**Security note:** the control API is unauthenticated by default (trusted LAN). Do not expose port `6790` to the public internet. `client_auth_token` in config is reserved for a future auth gate and is not enforced yet. Auth tokens in API responses are redacted.

## Quick start (Docker)

```bash
cp config.example.json data/config.json   # optional; auto-seeded on first run
docker compose up -d --build
```

Open `http://<host>:6790`.

Default DVR URLs (edit in **Settings** or `data/config.json` — replace with your Channels DVR host):

- `http://192.168.1.17:8089/devices/ANY/channels.m3u?format=ts&codec=copy`
- `http://192.168.1.17:8089/devices/ANY/guide/xmltv?duration=1209600`

If Channels DVR is offline at startup, the server still boots and serves any disk cache until refresh succeeds.

## Local development

### Server

```bash
cd server
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
TVMAESTRO_DATA_DIR=../data uvicorn tvmaestro.main:app --host 0.0.0.0 --port 6790 --reload
```

Or use `scripts/dev-server.sh` after creating `server/.venv`.

```bash
pip install -r requirements-dev.txt   # includes pytest
pytest -q
```

### Web UI

```bash
cd web
npm install
npm run dev
```

Vite proxies `/api` to `http://127.0.0.1:6790`.

To serve the built UI from the Python server (non-Docker), run `scripts/build-web.sh` — it builds `web/` and copies assets into `server/tvmaestro/web/`.

## Build automation

One entry point locally:

```bash
scripts/build-all.sh
# or: scripts/build-all.sh --skip-docker --only server,web
```

| Script | What it does |
|--------|----------------|
| `scripts/build-all.sh` | Server tests, web, Docker image, Android APK, Apple TV (skips missing toolchains) |
| `scripts/build-web.sh` | Vite production build → `server/tvmaestro/web/` |
| `scripts/build-android.sh` | `assembleDebug` APK |
| `scripts/build-appletv.sh` | tvOS Simulator build (needs full Xcode) |

**CI** (`.github/workflows/ci.yml`) runs on every push/PR: pytest, web build, Docker image, Android debug APK, and Apple TV simulator build (macOS runner). Artifacts: `web-dist`, `android-debug-apk`, `appletv-simulator-app`.

### Releases

Push a version tag to publish installable assets:

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions uploads the **Android APK** and **web dist zip** to the [Releases](https://github.com/matthewfkoch/TVMaestro/releases) page. **Apple TV TestFlight** uploads on the same tag via `.github/workflows/testflight.yml` (after GitHub secrets are configured — see `appletv/README.md`).

### Apple TV client

Open `appletv/TVMaestro.xcodeproj` in Xcode (tvOS 17+), run on an Apple TV, then **+ Device** with the LAN IP and port `9093`. Prefer **HLS** from Channels DVR. Leave the app open for the control API. Details below.

### TestFlight (recommended — same Apple account as Big Stick Invitational)

Big Stick uses `eas build --auto-submit` for iPhone. TVMaestro is native tvOS, so use Fastlane instead:

```bash
export FASTLANE_USER=your@email.com   # same Apple ID as EAS
export APPLE_TEAM_ID=XXXXXXXXXX       # same team as BSI
scripts/testflight-appletv.sh
```

One-time: create the tvOS app in App Store Connect and set `ascAppId` in `appletv/testflight.json` (like `ascAppId` in BSI's `eas.json`). Full steps: `appletv/docs/TESTFLIGHT.md`.

GitHub Actions TestFlight (API key secrets) is optional; local Apple ID upload does not need them.

### Xcode direct install (development)

```bash
open appletv/TVMaestro.xcodeproj
```

Pair the Apple TV in **Window → Devices and Simulators**, set your Team under Signing, select the TV as destination, and **Run** (⌘R).

### Android client

```bash
# Automated
scripts/build-android.sh
# or
cd android && ./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open `android/` in Android Studio if you prefer the IDE. Then in the web UI **+ Device** with the device LAN IP and port `9093`.

Multiview max depends on the SoC: capable devices report up to 4 panes; many Amlogic/MediaTek sticks are clamped to 1.

## API (summary)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/status` | Server + guide health |
| GET/PUT | `/api/config` | Settings (secrets redacted on GET) |
| POST | `/api/refresh` | Refresh M3U / XMLTV |
| GET | `/api/channels` | Channel list from M3U |
| GET | `/api/epg?from=&to=` | Programmes |
| GET/POST | `/api/devices` | Register Android endpoints |
| PATCH/DELETE | `/api/devices/{id}` | Update / remove device |
| POST | `/api/devices/{id}/cec` | `power_on`, `power_off`, `volume_up`, `volume_down`, `mute` |
| POST | `/api/devices/{id}/pair/start` · `/pair/finish` | Android TV Remote pairing |
| GET/POST | `/api/sessions` | List / start single or multiview |
| POST | `/api/sessions/{id}/stop` | Stop playback |
| POST | `/api/youtube/resolve` | Resolve YouTube URL via APITuner → MPEG-TS slot |
| GET | `/api/apituner/status` | APITuner reachability |
| GET | `/docs` | OpenAPI |

## Multiview layouts

`1`, `2x1`, `1x2`, `2x2` — max 4 streams; exactly one slot marked for audio. Empty middle slots are preserved in the grid.

## CEC

Volume/mute use the Android client's `AudioManager` (forwards over HDMI-CEC when volume control is enabled on the stick).

**Wake/Sleep (preferred):** pair **Android TV Remote** once from **Edit device → Pair** (PIN on the TV). The server uses the Google TV remote protocol (`androidtvremote2`) — no ADB. Enable One Touch Play / CEC TV Off in the device Power Control settings so the TV follows. Works on Shield / Google TV / Android TV (not Fire OS).

**Wake/Sleep (fallback):** if unpaired, the server can use **adb** `KEYCODE_WAKEUP` / `KEYCODE_SLEEP` when network debugging is on (`host:5555`) and Docker mounts host `~/.android` keys (see `docker-compose.yml`).

## YouTube

Set **APITuner base URL** in Settings. TVMaestro asks APITuner for a playable MPEG-TS URL (encoder relay), then plays it in the client like any other channel.

## License

See repository license when published.
