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

## Android client cannot connect

- verify the Android TV is on the same LAN as the TVMaestro server
- confirm the device is registered through the web UI
- check that port `9093` is reachable from the server to the client
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
