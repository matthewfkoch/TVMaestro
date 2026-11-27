# Changelog

## 0.4.6

- Harden the server API: validate device IDs, hosts, ports, and refresh intervals; restrict default CORS origins to localhost and Capacitor (configurable via `TVMAESTRO_CORS_ORIGINS`); enforce `client_auth_token` when configured.
- Improve server reliability: atomic JSON writes, remapped EPG disk cache, proper `3x3` multiview clamping, bounded session history with live-session recovery on restart, concurrent device heartbeats without redundant disk writes, pooled HTTP connections, and clean remote shutdown.
- Harden the Apple TV control HTTP server against malformed/oversized requests and stalled connections, and clean up unused in-app volume gain plumbing.
- Fix sample-mode field locking in Settings and memoization in the live multiview channel switcher.
- Expand automated tests and modernize CI/CD across server, web, mobile companion, Android TV, and Apple TV.

## 0.4.4

- Explain the server requirement and available TV controls on the companion connection screen.
- Include the current companion assets when preparing an iOS upload.
- Show a sync indicator in the guide when a sync error occurs.
- Update the web and Android build tools.

## 0.4.3

- Use port `6791` by default for new Android TV and Apple TV clients and new guide registrations. Explicitly saved ports remain unchanged.
- **Upgrade:** clients with no saved control port switch from `9093` to `6791`, while existing guide registrations keep their old port. Set the TV app back to `9093` or update its port under **Edit device** in the guide to match the address shown by the TV app. See [upgrade instructions](docs/TROUBLESHOOTING.md#device-offline-after-upgrading-to-043).
- Fix release promotion so a tested Docker candidate can be published when the build job is intentionally skipped.
- Use the tested TestFlight builds for App Store submissions and improve iOS companion signing.

## 0.4.2

- Ship the companion guide inside the iOS/Android app binary, with a View sample guide path for App Review and local-only WebView navigation.
- Change one live multiview pane from the guide without restarting the other streams. The server, web guide, Android TV, and Apple TV all speak the same slot-replace call.
- Publish the phone companion with this release: a signed Android APK on the GitHub Release, and an iOS build on TestFlight.
- The companion connect screen ignores invisible characters the iOS keyboard inserts into the server address.

## 0.4.1

- Move audio focus between panes without restarting playback.
- Add the phone and tablet companion. It loads the same guide as the browser.

## 0.4.0

- Apple TV plays the original MPEG-TS stream, including MPEG-2, with up to nine panes.

Earlier releases are on the [GitHub Releases](https://github.com/matthewfkoch/TVMaestro/releases) page.
