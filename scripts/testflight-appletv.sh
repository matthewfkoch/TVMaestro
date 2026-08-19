#!/usr/bin/env bash
# Build + upload TVMaestro to TestFlight — same Apple account as Big Stick Invitational.
#
# Big Stick uses:  cd apps/mobile && npx eas build --platform ios --profile production --auto-submit
# TVMaestro (native tvOS) uses Fastlane instead — EAS does not build tvOS Swift apps.
#
# One-time:
#   1. App Store Connect → Apps → + → tvOS app, bundle ID com.tvmaestro.client
#   2. Copy numeric Apple ID into appletv/testflight.json → ascAppId
#   3. export APPLE_TEAM_ID=XXXXXXXXXX   # same team as BSI
#   4. export FASTLANE_USER=your@email.com
#
# Or register automatically:
#   cd appletv && bundle exec fastlane setup
#
# Upload:
#   scripts/testflight-appletv.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/appletv"

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required." >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ -z "${FASTLANE_USER:-}" ]]; then
  echo "Apple ID for TestFlight (same as Big Stick / EAS):"
  read -r FASTLANE_USER
  export FASTLANE_USER
fi

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "Team ID (10 chars — developer.apple.com/account → Membership):"
  read -r APPLE_TEAM_ID
  export APPLE_TEAM_ID
fi

if ! command -v bundle >/dev/null 2>&1; then
  echo "Install bundler: gem install bundler" >&2
  exit 1
fi

bundle config set --local path 'vendor/bundle'
bundle install --quiet

echo "Building + uploading to TestFlight (Fastlane will prompt for Apple 2FA if needed)…"
bundle exec fastlane beta "$@"
