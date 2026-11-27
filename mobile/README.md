# TVMaestro companion

Phone and tablet guide for a TVMaestro server. Enter the server address and the app opens the bundled guide against that server’s API. Playback stays on the Android TV and Apple TV apps.

Bundle id: `com.tvmaestro.companion`. It is a separate install from the Android TV client.

## Connect

The first screen asks for the server address and port (default **6790**). The app checks `GET /api/status`, remembers the address, and opens the guide shipped in the app. Later launches reconnect on their own.

**View sample guide** opens the same UI with sample channels and no network. Use it for App Review or a quick look without a server.

In the guide, **Settings → Change server** returns to that screen. It is only shown inside this app.

The server is plain HTTP on the local network. Do not expose port `6790` to the internet. The first time you connect, iOS asks for local network permission. Addresses outside the local network must use HTTPS.

## Build

From the repo root, with no signing prompts:

```bash
scripts/build-mobile.sh
```

That builds the web guide into `mobile/www/guide`, then produces:

- Android debug APK: `mobile/android/app/build/outputs/apk/debug/app-debug.apk`
- iOS Simulator app, when Xcode is installed

The iOS build downloads the Capacitor frameworks itself, then compiles for the simulator with signing turned off.

The script points at Xcode and Homebrew Java 21 without changing `xcode-select`. It installs `openjdk@21` with Homebrew if that JDK is missing.

## Run on a device

Android:

```bash
cd mobile
npx cap run android
```

iOS device installs need a development team in Xcode. Run `scripts/build-mobile.sh` once so the Capacitor frameworks are local, then:

```bash
cd mobile
npx cap run ios --no-sync
```

`--no-sync` keeps the iOS project pointed at those local frameworks. A plain `npx cap sync` on iOS points it back at GitHub, and Xcode can stall while downloading them.

## TestFlight

Uses the same Apple credentials as the Apple TV upload (`appletv/.env`):

```bash
scripts/testflight-ios.sh
```

That registers `com.tvmaestro.companion` if needed, archives a Release build, and uploads it to TestFlight. Internal testers can install it from the TestFlight app once processing finishes. This is a separate app from the Apple TV client.

A push to `dev` that changes this app, or a manual run of `.github/workflows/testflight.yml`, uploads the same build when the App Store Connect secrets are set. A version tag does not upload another binary. The Android companion APK is attached to the GitHub Release for that tag.

## App Review access

The connection screen explains the server requirement and the app's features before connection. **View sample guide** opens a clearly labeled sample channel guide with no network. Playback stays on the television when connected to a real server.

The iOS upload preparation copies the current `www` assets and Capacitor configuration before archiving. Do not rely on assets left behind by an earlier simulator build.

App Store listing and submit steps: [`docs/APP_STORE.md`](docs/APP_STORE.md).
