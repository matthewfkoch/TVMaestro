# Release process

This project follows a lightweight release flow built around Git tags and GitHub Releases.

## Versioning

Use semantic versioning for releases:

- `MAJOR` for breaking changes
- `MINOR` for new features or significant behavior changes
- `PATCH` for bug fixes and stability updates

## Required version bumps

Before tagging a release, update all relevant version sources together:

- `server/tvmaestro/__version__.py`
- `web/package.json`
- Android `versionName` and `versionCode` in `android/app/build.gradle.kts`
- Apple TV `MARKETING_VERSION` in `appletv/TVMaestro.xcodeproj`
- Companion `version` in `mobile/package.json`, `versionName` and `versionCode` in `mobile/android/app/build.gradle`, and `MARKETING_VERSION` in `mobile/ios/App/App.xcodeproj`

## Tagging

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The release workflow will build and publish the appropriate artifacts.

## Release automation

The repository includes the following release-related workflows:

- `.github/workflows/release.yml` — publishes the Docker image, the Android TV APK, and the companion Android APK
- `.github/workflows/testflight.yml` — uploads the Apple TV app and the iOS companion to TestFlight when secrets are configured

## Notes

- Do not retag an already-published release.
- Prefer a clean `main` branch before tagging.
- If a release includes a platform-specific breaking change, note it explicitly in the GitHub release notes.
