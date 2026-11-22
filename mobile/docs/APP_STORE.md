# App Store listing (iOS companion)

App Store Connect id `6821197390`, bundle id `com.tvmaestro.companion`.

## Already in the repo

- [PrivacyInfo.xcprivacy](../ios/App/App/PrivacyInfo.xcprivacy) — tracking off, no collected data types, UserDefaults reason `CA92.1` (server host, port, scheme).
- [docs/privacy.md](../../docs/privacy.md) and [docs/companion.md](../../docs/companion.md) — privacy and support pages.
- English listing files in [fastlane/metadata](../fastlane/metadata).
- Review notes explain **View sample guide** and that the WebView does not load remote pages.

## Upload listing (no review submission)

```bash
set -a
source appletv/.env   # or ~/.tvmaestro-testflight.env
set +a
cd mobile && BUNDLE_GEMFILE=../appletv/Gemfile bundle exec fastlane ios metadata
```

Review contact stays on your machine (gitignored):

- `mobile/fastlane/metadata/review_information/first_name.txt`
- `mobile/fastlane/metadata/review_information/last_name.txt`
- `mobile/fastlane/metadata/review_information/phone_number.txt`
- `mobile/fastlane/metadata/review_information/email_address.txt`

## Submit for review

1. Capture iPhone 6.9" (1320×2868) and iPad 13" (2064×2752) screenshots: connect, sample guide, settings. Keep them under `mobile/fastlane/screenshots/en-US/`.
2. Fill review contact files if missing.
3. In App Store Connect, price Free and App Privacy = Data Not Collected.
4. Run:

```bash
scripts/submit-ios.sh
```

That uploads metadata, screenshots, a new Release build, and submits for review when the contact files are present.
