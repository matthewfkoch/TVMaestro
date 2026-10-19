# Release process

Candidate builds come from `dev`. A version tag promotes the server image you already tested and publishes the Android APKs. App Store review uses the TestFlight build you already uploaded.

## Branches

Land day-to-day work on `dev`. A push to `dev` runs CI and publishes the Docker image as `:dev` and as an immutable `sha-<12-character commit sha>` tag. It does not publish `:latest`, Android APKs, or a GitHub Release.

Move `main` only by fast-forwarding it to the commit you are releasing, then tag that same commit. That keeps the TestFlight binary, the Docker digest, and the Android APKs on one sha.

## Versioning

Use semantic versioning for releases:

- `MAJOR` for breaking changes
- `MINOR` for new features or significant behavior changes
- `PATCH` for bug fixes and stability updates

Before a TestFlight upload, bump the marketing version on `dev` in every version source together:

- `server/tvmaestro/__version__.py`
- `web/package.json`
- Android `versionName` and `versionCode` in `android/app/build.gradle.kts`
- Apple TV `MARKETING_VERSION` in `appletv/TVMaestro.xcodeproj`
- Companion `version` in `mobile/package.json`, `versionName` and `versionCode` in `mobile/android/app/build.gradle`, and `MARKETING_VERSION` in `mobile/ios/App/App.xcodeproj`
- `CHANGELOG.md`
- `appletv/fastlane/metadata/en-US/release_notes.txt` (What’s New)

Upload those notes with `bundle exec fastlane metadata` before you submit. The submit lane skips metadata.

Bump `versionCode` with each Android release. A repeated code will not install over the previous APK.

Apple build numbers are not committed. TestFlight sets the next build to one higher than the latest build App Store Connect already has for that marketing version. After a version is released, the next TestFlight upload needs a higher marketing version.

## TestFlight

Pushes to `dev` that change `appletv/**` or `mobile/**` upload the Apple TV app and the iOS companion to TestFlight. You can also run the TestFlight workflow by hand, including companion-only. Version tags do not upload another binary.

TestFlight builds expire 90 days after upload.

## Candidate checks

Before tagging, require successful CI, Docker candidate publication, and both TestFlight uploads for the exact candidate commit. Smoke-test fresh installs and upgrades from the previous release on Android TV and Apple TV: confirm the displayed control port matches the guide registration, tune a channel, replace a multiview pane, move audio focus, and verify paired wake/sleep and app launch. For 0.4.3, follow the [port upgrade instructions](TROUBLESHOOTING.md#device-offline-after-upgrading-to-043), including an upgrade where the TV settings were never saved and one with a custom saved port.

## Tagging

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

If that commit already has a `sha-<12>` image, the release workflow retags that digest to `:X.Y.Z` and `:latest`. Otherwise it builds the image from source. The tag also builds the Android TV APK, the companion Android APK, and the GitHub Release.

Do not retag an already-published release.

Publish `:latest` before you release an approved app that depends on new server behavior.

## App Store review

Run the App Store workflow by hand. It does not build a new binary. Choose the platform (`tvos`, `ios`, or both), the marketing version, and the processed TestFlight build number. Approval does not release the app unless you set automatic release. The App Store Connect API key must be App Manager or Admin.

The workflow fails if that build is still processing. A metadata rejection can resubmit the same build number. A binary rejection needs a new TestFlight upload, then a submit of that new number.

The iOS companion submit lane refuses to run until `mobile/fastlane/metadata` exists. The first tvOS submission still needs the listing work in [appletv/docs/APP_STORE.md](../appletv/docs/APP_STORE.md).

Locally, from `appletv`:

```bash
BUILD_NUMBER=21 bundle exec fastlane submit
```

`AUTOMATIC_RELEASE=true` releases the app when Apple approves it. The default is to leave it unreleased.
