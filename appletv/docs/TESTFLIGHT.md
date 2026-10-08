# TestFlight (Apple TV)

TVMaestro is a native tvOS app, so uploads use Fastlane.

## Prerequisites

- An enrolled Apple Developer Program membership
- Xcode 15+ with your Apple ID signed in (**Xcode → Settings → Accounts**)
- tvOS app in App Store Connect (one-time)

## One-time setup

### Step 1 — Register the bundle ID (Developer portal)

There is **no tvOS platform picker** here. Since Xcode 11.4, one App ID works for iOS, macOS, tvOS, and watchOS.

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** → **App IDs** → **App**
2. Description: **TVMaestro**
3. Bundle ID: **Explicit** → **`com.tvmaestro.client`**
4. Leave capabilities at defaults → **Register**

**Skip this step** if you run `fastlane setup` below — it creates the identifier for you.

### Step 2 — Create the App Store Connect app

**Option A — App Store Connect UI**:

1. [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**
2. Platforms: check **tvOS** only (Apple TV) · Name: **TVMaestro** · Bundle ID: **`com.tvmaestro.client`**
3. **App Information** → copy the numeric **Apple ID** → paste into `appletv/testflight.json`:

```json
"ascAppId": "1234567890"
```

**Option B — Fastlane** (creates the app record for you):

```bash
export FASTLANE_USER=your@email.com
export APPLE_TEAM_ID=XXXXXXXXXX
cd appletv && bundle install && bundle exec fastlane setup
```

Then update `testflight.json` with the numeric Apple ID from App Store Connect.

## Store the app-specific password (local only)

Do **not** put this in git. Fastlane reads `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`.

**Recommended:** `appletv/.env` (already gitignored). Copy the example and fill it in:

```bash
cp appletv/.env.example appletv/.env
# edit appletv/.env — Apple ID, Team ID, app-specific password
scripts/testflight-appletv.sh
```

Same keys also work in `~/.tvmaestro-testflight.env` if you prefer keeping secrets outside the repo.

Create the password at [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security** → **App-Specific Passwords**.

## Build + upload

```bash
scripts/testflight-appletv.sh
```

Or export vars in the shell instead of using `.env`:

```bash
export FASTLANE_USER=your@email.com
export APPLE_TEAM_ID=XXXXXXXXXX
export FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD='xxxx-xxxx-xxxx-xxxx'
scripts/testflight-appletv.sh
```

Or interactively (script prompts for email + team):

```bash
scripts/testflight-appletv.sh
```

Fastlane builds a Release tvOS IPA and uploads it to App Store Connect. Approve 2FA on your phone if prompted. The upload does not create a shareable link.

## Install on Apple TV

Wait until the build finishes processing in App Store Connect → **TestFlight**.

### Internal testers

App Store Connect users on your team can install without a public link.

1. **TestFlight** → **Internal Testing** → add testers
2. On the Apple TV: open **TestFlight** → **TVMaestro** → Install

### Public link

For people who are not on your App Store Connect team:

1. **TestFlight** → create an external group and add the build
2. Enable **Public Link** on that group
3. The first build added to an external group goes through Beta App Review before the link works
4. Send the link

Testers install it like this:

1. Use an Apple TV on tvOS 18 or later, and an iPhone or iPad signed into the same App Store account
2. Install **TestFlight** on both
3. Open the public link on the phone and accept
4. Open **TestFlight** on the Apple TV and install TVMaestro

The link is opened on the phone, not on the Apple TV.

An email invite is the other path. The tester opens the email, follows **View in TestFlight**, and redeems the code in **TestFlight** on the Apple TV.

After install: web UI → **+ Device** → Apple TV LAN IP → port **9093**.

## CI (optional)

GitHub Actions workflow `.github/workflows/testflight.yml` uses `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, and `APPLE_TEAM_ID`. Local uploads via Apple ID (above) do not need those secrets.
