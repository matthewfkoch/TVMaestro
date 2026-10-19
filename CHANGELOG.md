# Changelog

## 0.4.3

- Use port `6791` by default for new Android TV and Apple TV clients and new guide registrations. Explicitly saved ports remain unchanged.
- **Upgrade:** clients with no saved control port switch from `9093` to `6791`, while existing guide registrations keep their old port. Set the TV app back to `9093` or update its port under **Edit device** in the guide to match the address shown by the TV app. See [upgrade instructions](docs/TROUBLESHOOTING.md#device-offline-after-upgrading-to-043).
- Fix release promotion so a tested Docker candidate can be published when the build job is intentionally skipped.
- Use the tested TestFlight builds for App Store submissions and improve iOS companion signing.

## 0.4.2

- Change one live multiview pane from the guide without restarting the other streams. The server, web guide, Android TV, and Apple TV all speak the same slot-replace call.
- Publish the phone companion with this release: a signed Android APK on the GitHub Release, and an iOS build on TestFlight.
- The companion connect screen ignores invisible characters the iOS keyboard inserts into the server address.

## 0.4.1

- Move audio focus between panes without restarting playback.
- Add the phone and tablet companion. It loads the same guide as the browser.

## 0.4.0

- Apple TV plays the original MPEG-TS stream, including MPEG-2, with up to nine panes.

Earlier releases are on the [GitHub Releases](https://github.com/matthewfkoch/TVMaestro/releases) page.
