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

**CI** (`.github/workflows/ci.yml`) runs on pushes to `main` and `dev`, and on pull requests: pytest, web build, Docker image, Android TV debug APK, Apple TV build, companion Android debug APK, and companion iOS Simulator build. Artifacts: `web-dist`, `android-debug-apk`, `appletv-app`, `companion-android-debug-apk`, `companion-ios-app`.

### Releases

Day-to-day work lands on `dev`. A push there runs CI and publishes `ghcr.io/matthewfkoch/tvmaestro:dev` plus an immutable `sha-<12-character commit>` tag. It does not move `:latest`.

Pushes to `dev` that change `appletv/` or `mobile/` upload the Apple TV app and the iOS companion to TestFlight. You can also run `.github/workflows/testflight.yml` by hand. Version tags do not upload another Apple binary. Local uploads with `scripts/testflight-appletv.sh` and `scripts/testflight-ios.sh` do not need the GitHub secrets. If `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, or `APPLE_TEAM_ID` is missing, the TestFlight jobs skip.

When a TestFlight build is the one you want to ship, fast-forward `main` to that commit and tag it:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

`.github/workflows/release.yml` then:

1. Retags the existing `sha-<12-character commit>` image to `ghcr.io/matthewfkoch/tvmaestro:<version>` and `:latest` when that image exists. It builds from source only when the sha image was never published.
2. Builds the Android TV APK and the companion Android APK, and attaches both to a [GitHub Release](https://github.com/matthewfkoch/TVMaestro/releases) on this repo

A manual run of the Release workflow (no tag) publishes `:dev` and the sha tag only. Do not retag a version that already shipped.

App Store review does not build a new binary. Run `.github/workflows/appstore.yml` with the marketing version and the processed TestFlight build number. Approval leaves the app unreleased unless you opt in, so you can publish `:latest` first when the app depends on a new server. The API key must be App Manager or Admin. The iOS companion is not submitted until `mobile/fastlane/metadata` exists. See [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md).

If the package is still private (the default when the repo started private), open **Packages → tvmaestro → Package settings**, link it to this repo, and set visibility to **Public** so `docker pull` works from the public registry.

Bump these together on `dev` before the TestFlight upload. Fastlane chooses the Apple build number from App Store Connect and does not commit it. `Info.plist` reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`.

- `server/tvmaestro/__version__.py`
- `web/package.json`
- Android `versionName` and `versionCode` in `android/app/build.gradle.kts`
- Apple TV `MARKETING_VERSION` in `appletv/TVMaestro.xcodeproj`
- Companion `version` in `mobile/package.json`, `versionName` and `versionCode` in `mobile/android/app/build.gradle`, and `MARKETING_VERSION` in `mobile/ios/App/App.xcodeproj`
- `CHANGELOG.md` and `appletv/fastlane/metadata/en-US/release_notes.txt`

**Signing:** release APKs are signed with the repository secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`. The same keystore signs the Android TV client and the companion. Do not generate a new keystore. Upgrades install over a previous release only when both APKs use this key. If those secrets are missing, the workflow attaches debug APKs (`tvmaestro-android-<version>-debug.apk` and `tvmaestro-companion-<version>-debug.apk`) instead.

### Apple TV client

Open `appletv/TVMaestro.xcodeproj` in Xcode (tvOS 17+), run on an Apple TV, then **+ Device** and choose **Apple TV** with the LAN IP and port `9093`. Pair it once under **Edit device** (PIN on the Apple TV).

### TestFlight

```bash
export FASTLANE_USER=your@email.com
export APPLE_TEAM_ID=XXXXXXXXXX
scripts/testflight-appletv.sh
```

One-time: create the tvOS app in App Store Connect and set `ascAppId` in `appletv/testflight.json`. Full steps, including a public link for other Apple TVs: `appletv/docs/TESTFLIGHT.md`.

GitHub Actions upload is `.github/workflows/testflight.yml` on `dev` (when `appletv/` or `mobile/` changes) or when you run it by hand. It needs the API key secrets above. The same workflow uploads the iOS companion. Local Apple ID upload does not. The upload places the build in App Store Connect; the public link is turned on there after processing.

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
| GET/POST | `/api/sessions/{id}/audio` | Read or move audio focus (`index`) without restarting streams |
| POST | `/api/sessions/{id}/slot` | Replace one live pane (`index`, `channel_id`, or null to clear) |
| POST | `/api/youtube/resolve` | Resolve YouTube URL via APITuner → MPEG-TS slot |
| GET | `/api/apituner/status` | APITuner reachability |
| GET | `/docs` | OpenAPI |

## Multiview layouts

`1`, `2x1`, `1x2`, `2x2`, `3x3`. Exactly one slot is marked for audio. Empty slots stay in the grid.

Apple TV reports up to nine panes (`3x3`). Android TV reports up to four panes (`2x2`); many Amlogic/MediaTek sticks are clamped to one.

## CEC

Volume/mute use the Android client's `AudioManager` (forwards over HDMI-CEC when volume control is enabled on the stick). On **Apple TV**, volume/mute send the same Companion button presses as the Siri Remote (`volume_up` / `volume_down` / `mute`) after the device is paired. The television follows only if Control TVs and Receivers is enabled on that Apple TV. Wake and Sleep of a paired Apple TV use the Companion protocol (`power_on` / `power_off`). Open still launches the app (`POST /api/devices/{id}/launch`, or automatically when a tune finds the app closed). Wake alone does not open the app.

**Wake/Sleep (Apple TV):** pair once from **Edit device → Pair** (PIN on the Apple TV). The server uses the Companion protocol. The television follows only if **Control TVs and Receivers** is on.

**Wake/Sleep (preferred):** pair **Android TV Remote** once from **Edit device → Pair** (PIN on the TV). The server uses the Google TV remote protocol (`androidtvremote2`) — no ADB. Enable One Touch Play / CEC TV Off in the device Power Control settings so the TV follows. Works on Shield / Google TV / Android TV (not Fire OS, not Apple TV).

**Wake/Sleep (fallback):** if unpaired, the server can use **adb** `KEYCODE_WAKEUP` / `KEYCODE_SLEEP` when network debugging is on (`host:5555`) and Docker mounts host `~/.android` keys (see `docker-compose.yml`).

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
