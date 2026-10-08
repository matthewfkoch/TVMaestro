# App Store listing (not submitted)

The tvOS app record already exists (`com.tvmaestro.client`, App Store Connect id `6802899349`). Listing copy, the age rating, and review notes are in the repo. Nothing has been uploaded, and the app has not been submitted for review.

## Already in the repo

- [PrivacyInfo.xcprivacy](../TVMaestro/PrivacyInfo.xcprivacy) is in the app target. Tracking is off, no data types are collected, and `UserDefaults` is declared with reason `CA92.1` (the control port, optional auth token, and guide flags).
- [docs/privacy.md](../../docs/privacy.md) is the privacy policy. The store URL is `https://github.com/matthewfkoch/TVMaestro/blob/main/docs/privacy.md`. That page 404s until the file is on the public `main` branch.
- English listing files are in [fastlane/metadata](../fastlane/metadata): name, subtitle, description, keywords, promotional text, release notes, support URL, and marketing URL. Copyright is `2026 Matthew Koch`. Primary category is Entertainment.
- `en-US/privacy_url.txt` is the GitHub privacy URL. `en-US/apple_tv_privacy_policy.txt` is the same policy as plain text, because Apple TV shows that text on the device instead of opening a link.
- `metadata/rating_config.json` answers the age-rating questions as none / false, including unrestricted web access. The expected rating is 4+.
- `metadata/review_information/notes.txt` explains local-network HTTP and that playback starts when the guide sends a session. Name, phone, and email are not in git.

## Upload the draft later

This only fills the App Store Connect draft. It does not upload a binary, screenshots, or submit for review.

```bash
set -a
source appletv/.env   # or ~/.tvmaestro-testflight.env
set +a
cd appletv && bundle exec fastlane metadata
```

Uses the same credentials as TestFlight: `FASTLANE_USER` or `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_KEY_PATH`, plus `APPLE_TEAM_ID`. The lane reads the marketing version from the Xcode project and targets `appletvos`.

Fastlane skips “What’s New” on the first version. Add review contact only on your machine, as these files (they are gitignored):

- `appletv/fastlane/metadata/review_information/first_name.txt`
- `appletv/fastlane/metadata/review_information/last_name.txt`
- `appletv/fastlane/metadata/review_information/phone_number.txt`
- `appletv/fastlane/metadata/review_information/email_address.txt`

## Still required before Submit for Review

1. Finish and test the app, including a way for the reviewer to start playback. The idle screen alone is not enough.
2. Capture Apple TV screenshots at 1920×1080 (up to 10): idle, settings, and a real playback grid. Keep them in `appletv/fastlane/screenshots/en-US/`. The metadata lane does not upload them; add them in App Store Connect before you submit.
3. Push `docs/privacy.md` to `main` so the privacy URL loads.
4. Fill in the review contact files above, then run `bundle exec fastlane metadata`.
5. In App Store Connect, set the price to Free and App Privacy to Data Not Collected.
6. Submit for Review when you want to.
