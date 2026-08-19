#!/usr/bin/env bash
# Build and upload the tvOS app to TestFlight (requires App Store Connect API key).
#
# One-time setup:
#   1. Create app in App Store Connect: bundle ID com.tvmaestro.client, Apple TV platform
#   2. App Store Connect → Users and Access → Keys → create API key (Admin or App Manager)
#   3. Export AuthKey_XXXXXX.p8 and set env vars below
#
# Usage:
#   export APPLE_TEAM_ID=XXXXXXXXXX
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_API_KEY_PATH=$HOME/.appstoreconnect/AuthKey_XXXXXX.p8
#   scripts/testflight-appletv.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/appletv"

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required (not Command Line Tools only)." >&2
  exit 1
fi

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
: "${ASC_API_KEY_PATH:?Set ASC_API_KEY_PATH to your .p8 file}"

if [[ ! -f "$ASC_API_KEY_PATH" ]]; then
  echo "ASC API key not found: $ASC_API_KEY_PATH" >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! command -v bundle >/dev/null 2>&1; then
  echo "Ruby bundler not found. Install: gem install bundler" >&2
  exit 1
fi

bundle config set --local path 'vendor/bundle'
bundle install --quiet
bundle exec fastlane beta "$@"
