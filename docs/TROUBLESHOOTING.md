# Troubleshooting

This guide covers the most common issues reported when setting up or running TVMaestro.

## The web UI loads but no guide data appears

Check the following:

- `data/config.json` contains valid Channels DVR URLs
- the Channels DVR host is reachable from the machine running TVMaestro
- the server is healthy at `/api/status`
- the container has permission to write to the `data/` directory

If Channels DVR is down at startup, the server still boots but may serve cached data until the next successful refresh.

## Docker container starts but the guide is blank

Common causes:

- the `data/` volume is missing or not writable
- the Channels DVR endpoint is not reachable
- the server cannot parse the M3U or XMLTV feed

Useful checks:

```bash
docker logs tvmaestro
curl http://localhost:6790/api/status
```

## Device offline after upgrading to 0.4.3

The default TV control port changed from `9093` to `6791`. The server's own port remains `6790`. Existing guide registrations and explicitly saved TV control ports are preserved. A TV app that never saved its control port starts using `6791` after this upgrade.

Before upgrading, you can explicitly save `9093` in the TV app's Settings to retain the old port. On Apple TV, if saving an unchanged value does nothing, change it to another available port and then back to `9093`.

After upgrading:

1. Open the TVMaestro app on the TV and note the control port in its displayed address or Settings.
2. In the web guide, open **Edit device** for that TV and set the port to the same number. Alternatively, set the TV app's control port back to `9093` to match the existing registration.
3. Allow the chosen port through any LAN firewall, then verify the device is online and tune a channel.

Keep the existing device registration and pairing. A port-only change does not require deleting or re-pairing the device. When adding an older client to the upgraded guide, enter its actual port (usually `9093`) instead of accepting the new default.

## Android client cannot connect

- verify the Android TV is on the same LAN as the TVMaestro server
- confirm the device is registered through the web UI
- check that the TV control port (default `6791`) is reachable from the server to the client
- if the client is running behind a firewall, ensure traffic is allowed on the LAN

## Apple TV cannot pair or open from the guide

- make sure the Apple TV is on the same LAN as the server
- pair the device once under **Edit device → Pair**
- confirm the Apple TV app is open or that pairing credentials are available
- verify that **Control TVs and Receivers** is enabled if wake/sleep behavior is expected

## Android SDK missing for local builds

If Gradle fails due to missing SDK tools, install Android Studio and set the SDK path in `android/local.properties`.

Example:

```properties
sdk.dir=/Users/yourname/Library/Android/sdk
```

## Xcode tools missing for Apple TV builds

The tvOS project requires Xcode 15+ with the tvOS SDK. If the build fails, verify the Xcode command line tools and Apple Developer signing configuration.

## Browser fails to load the UI or API

- confirm the server is running on port `6790`
- check the browser devtools for failed network requests to `/api/*`
- if using Docker, ensure the port mapping is exposed correctly

## Security / network exposure

The control API is intentionally unauthenticated by default. Do not expose port `6790` to the public internet without additional auth and network protections.

## Getting more help

- read the project README at the repo root
- check the issue tracker for similar reports
- use the repository's security reporting flow for vulnerabilities
