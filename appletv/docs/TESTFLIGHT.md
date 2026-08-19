# TestFlight (Apple TV)

Same **Apple Developer account** as Big Stick Invitational — BSI uses **EAS** for iPhone; TVMaestro uses **Fastlane** because native tvOS is not supported by Expo/EAS.

## Prerequisites

- Same enrolled Apple Developer Program as BSI ($99/yr — you already have this for TestFlight)
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

**Option A — App Store Connect UI** (mirrors BSI `eas.json` → `ascAppId`):

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

## Build + upload (like BSI `eas build --auto-submit`)

```bash
scripts/testflight-appletv.sh
```

Or export vars in the shell instead of using `.env`:

```bash
export FASTLANE_USER=your@email.com      # same Apple ID as EAS / Big Stick
export APPLE_TEAM_ID=XXXXXXXXXX          # same team as BSI
export FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD='xxxx-xxxx-xxxx-xxxx'
scripts/testflight-appletv.sh
```

Or interactively (script prompts for email + team):

```bash
scripts/testflight-appletv.sh
```

Fastlane builds a Release tvOS IPA and uploads to TestFlight. Approve 2FA on your phone if prompted.

## Install on Apple TV

1. Wait for processing in App Store Connect → **TestFlight**  
2. **Internal testing**: add testers (same as BSI — your Apple ID is already internal)  
3. On Apple TV: open **TestFlight** → **TVMaestro** → Install  
4. Web UI → **+ Device** → Apple TV LAN IP → port **9093**

## CI (optional)

GitHub Actions workflow `.github/workflows/testflight.yml` uses App Store Connect **API key** secrets (`ASC_*`). Local uploads via Apple ID (above) do not need those secrets.

## Compare to Big Stick Invitational

| | Big Stick (iPhone) | TVMaestro (Apple TV) |
|--|-------------------|----------------------|
| Build tool | EAS (`eas build`) | Fastlane / Xcode |
| Upload | `--auto-submit` | `fastlane beta` |
| Config | `apps/mobile/eas.json` | `appletv/testflight.json` |
| Apple account | Same | Same |
