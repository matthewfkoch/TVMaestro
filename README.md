# TVMaestro

[![CI](https://github.com/matthewfkoch/TVMaestro/actions/workflows/ci.yml/badge.svg)](https://github.com/matthewfkoch/TVMaestro/actions/workflows/ci.yml)
[![Docker](https://img.shields.io/badge/container-ghcr.io%2Ftvmaestro-blue)](https://github.com/matthewfkoch/TVMaestro/pkgs/container/tvmaestro)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20TV%20%7C%20tvOS%20%7C%20Web-lightgrey)](README.md)

<img src="branding/logo-app-icon-512.png" alt="TVMaestro" width="96" height="96" />

EPG orchestrator for [Channels DVR](https://getchannels.com/) with a polished web guide and an Android TV client that plays streams (including up to 4-way multiview). Optional YouTube/encoder path support via APITuner is also included.

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution flow and local development setup
- [SECURITY.md](SECURITY.md) — security reporting and vulnerability disclosure
- [docs/README.md](docs/README.md) — documentation index
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common setup and runtime issues
- [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md) — release workflow and versioning
- [docs/DEVELOPER_QUICKSTART.md](docs/DEVELOPER_QUICKSTART.md) — local contributor quickstart

## Architecture

- **Server** (Python / FastAPI, port **6790**) — ingests Channels DVR M3U + XMLTV, device registry, session orchestration
- **Web UI** (React / Vite) — broadcast-style EPG, tune sheet, multiview composer, CEC controls
- **Android client** (Kotlin / Media3 ExoPlayer, control API **9093**) — plays HLS/MPEG-TS; best-effort HDMI-CEC
- **Apple TV** (`appletv/`) — tvOS client (same control API as Android; KSPlayer plays MPEG-TS, including MPEG-2; up to nine-pane multiview)

Control plane: browser → TVMaestro server → Android TV or Apple TV client.  
Media plane: the client pulls stream URLs directly from Channels (or APITuner).

**Security note:** the control API is unauthenticated by default (trusted LAN). Do not expose port `6790` to the public internet. `client_auth_token` in config is reserved for a future auth gate and is not a substitute for network isolation.

## Quick start (Docker)

### From GitHub Container Registry (releases)

```bash
docker compose pull
docker compose up -d
```

Or without Compose:

```bash
mkdir -p data
docker run -d \
  --pull always \
  --name tvmaestro \
  -p 6790:6790 \
  -v "$(pwd)/data:/data" \
  -v "$HOME/.android:/root/.android:ro" \
  --restart unless-stopped \
  ghcr.io/matthewfkoch/tvmaestro:latest
```

`docker compose up -d` pulls `ghcr.io/matthewfkoch/tvmaestro:latest` before it starts. `docker run` needs `--pull always`, or an image already on disk is reused.

Open `http://<host>:6790`. Config is auto-seeded into `data/` on first run (`config.example.json` is optional).

### Build locally

```bash
docker compose up -d --build --pull never
```

Channels DVR URLs are blank by default. Configure them in **Settings** or `data/config.json` using your Channels DVR hostname:

- `http://channels-dvr.local:8089/devices/ANY/channels.m3u?format=ts&codec=copy`
- `http://channels-dvr.local:8089/devices/ANY/guide/xmltv?duration=1209600`

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

**CI** (`.github/workflows/ci.yml`) runs on every push/PR: pytest, web build, Docker image, Android debug APK, and Apple TV simulator build (macOS runner). Artifacts: `web-dist`, `android-debug-apk`, and Apple TV simulator outputs.

### Releases

Tagged releases (`v*`) trigger `.github/workflows/release.yml`, which:

1. Runs the server tests, then publishes a multi-arch image (`linux/amd64` + `linux/arm64`) to GitHub Container Registry: `ghcr.io/matthewfkoch/tvmaestro:<version>` and `:latest`
2. Builds the Android TV APK and attaches it to a [GitHub Release](https://github.com/matthewfkoch/TVMaestro/releases) on this repo

The same tag triggers `.github/workflows/testflight.yml`, which uploads the Apple TV build to TestFlight when `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, and `APPLE_TEAM_ID` are set. If those secrets are absent, the workflow will fail fast.

A manual run of the Release workflow (no tag) publishes `:dev` only. Do not retag a version that already shipped.

If the package is still private (the default when the repo started private), open **Packages → tvmaestro → Package settings**, link it to this repo, and set visibility to **Public** so `docker pull` works from the public registry.

Bump these together, then tag:

- `server/tvmaestro/__version__.py`
- `web/package.json`
- Android `versionName` and `versionCode` in `android/app/build.gradle.kts`
- Apple TV `MARKETING_VERSION` in `appletv/TVMaestro.xcodeproj` (`Info.plist` reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`; Fastlane increments the build number on upload)

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

**Signing:** release APKs are signed with the repository secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`. Do not generate a new keystore. Upgrades install over a previous signed release.

### Apple TV client

Open `appletv/TVMaestro.xcodeproj` in Xcode (tvOS 17+), run on an Apple TV, then **+ Device** and choose **Apple TV** with the LAN IP and port `9093`. Pair it once under **Edit device** (PIN on the Apple TV).

### TestFlight

```bash
export FASTLANE_USER=your@email.com
export APPLE_TEAM_ID=XXXXXXXXXX
scripts/testflight-appletv.sh
```

One-time: create the tvOS app in App Store Connect and set `ascAppId` in `appletv/testflight.json`. Full steps, including a public link for other Apple TVs: `appletv/docs/TESTFLIGHT.md`.

GitHub Actions upload is `.github/workflows/testflight.yml` and needs the API key secrets above. Local Apple ID upload does not. The upload places the build in App Store Connect; the public link can then be used to install on remote Apple TVs.

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
| GET/POST | `/api/devices` | Register Android TV / Apple TV endpoints |
| PATCH/DELETE | `/api/devices/{id}` | Update / remove device |
| POST | `/api/devices/{id}/cec` | `power_on`, `power_off`, `volume_up`, `volume_down`, `mute` |
| POST | `/api/devices/{id}/pair/start` · `/pair/finish` | Android TV Remote pairing, or Apple TV Companion pairing |
| POST | `/api/devices/{id}/launch` | Open the TVMaestro app on a paired Apple TV |
| GET/POST | `/api/sessions` | List / start single or multiview |
| POST | `/api/sessions/{id}/stop` | Stop playback |
| POST | `/api/youtube/resolve` | Resolve YouTube URL via APITuner → MPEG-TS slot |
| GET | `/api/apituner/status` | APITuner reachability |
| GET | `/docs` | OpenAPI |

## Multiview layouts

`1`, `2x1`, `1x2`, `2x2`, `3x3`. Exactly one slot is marked for audio. Empty slots stay in the grid.

Apple TV reports up to nine panes (`3x3`). Android TV reports up to four panes (`2x2`); many Amlogic/MediaTek sticks are clamped to one.

## CEC

Volume/mute use the Android client's `AudioManager` (forwards over HDMI-CEC when volume control is enabled on the stick). On **Apple TV**, volume/mute send the same Companion button presses as the Siri Remote.

**Wake/Sleep (Apple TV):** pair once from **Edit device → Pair** (PIN on the Apple TV). The server uses the Companion protocol. The television follows only if **Control TVs and Receivers** is on.

**Wake/Sleep (preferred):** pair **Android TV Remote** once from **Edit device → Pair** (PIN on the TV). The server uses the Google TV remote protocol (`androidtvremote2`) — no ADB. Enable One-Time Pairing from the TV settings.

**Wake/Sleep (fallback):** if unpaired, the server can use **adb** `KEYCODE_WAKEUP` / `KEYCODE_SLEEP` when network debugging is on (`host:5555`) and Docker mounts host `~/.android` keys (see `docs/` for details).

## YouTube

Set **APITuner base URL** in Settings. TVMaestro asks APITuner for a playable MPEG-TS URL (encoder relay), then plays it on the selected Android TV or Apple TV.

## License

[MIT](LICENSE) © 2026 Matthew Koch.

The Apple TV app links [KSPlayer](https://github.com/kingslay/KSPlayer) and [FFmpegKit](https://github.com/kingslay/FFmpegKit), GPL-3.0-only. See [NOTICE](NOTICE).

## Contributing

For development setup and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Please report security issues privately via the repository's [security advisory form](https://github.com/matthewfkoch/TVMaestro/security/advisories/new) or the maintainer's GitHub profile. See [SECURITY.md](SECURITY.md) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes and project updates.
