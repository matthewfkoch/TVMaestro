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
- Android metadata in `android/app/build.gradle.kts`
- Apple TV marketing version in `appletv/TVMaestro.xcodeproj`

## Tagging

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The release workflow will build and publish the appropriate artifacts.

## Release automation

The repository includes the following release-related workflows:

- `.github/workflows/release.yml` — publishes Docker image and Android APK
- `.github/workflows/testflight.yml` — uploads Apple TV build to TestFlight when secrets are configured

## Notes

- Do not retag an already-published release.
- Prefer a clean `main` branch before tagging.
- If a release includes a platform-specific breaking change, note it explicitly in the GitHub release notes.
