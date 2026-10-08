#!/usr/bin/env bash
# Build + upload TVMaestro to TestFlight.
#
# Native tvOS builds go through Fastlane.
#
# One-time:
#   1. App Store Connect → Apps → + → tvOS app, bundle ID com.tvmaestro.client
#   2. Copy numeric Apple ID into appletv/testflight.json → ascAppId
#   3. export APPLE_TEAM_ID=XXXXXXXXXX
#   4. export FASTLANE_USER=your@email.com
#
# Or register automatically:
#   cd appletv && bundle exec fastlane setup
#
# Upload:
#   scripts/testflight-appletv.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load local secrets if present (gitignored). Do not commit this file.
#   appletv/.env  or  ~/.tvmaestro-testflight.env
load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
}
load_env_file "$HOME/.tvmaestro-testflight.env"
load_env_file "$ROOT/appletv/.env"

cd "$ROOT/appletv"

XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
if [[ -d "$XCODE_APP/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

xcodebuild_bin="${DEVELOPER_DIR:-}/usr/bin/xcodebuild"
if [[ ! -x "$xcodebuild_bin" ]]; then
  xcodebuild_bin="$(command -v xcodebuild || true)"
fi

if [[ -z "$xcodebuild_bin" || ! -x "$xcodebuild_bin" ]] || ! "$xcodebuild_bin" -version >/dev/null 2>&1; then
  echo "Full Xcode is required (Command Line Tools alone cannot build tvOS)." >&2
  echo "" >&2
  if [[ -d "$XCODE_APP" ]]; then
    echo "Xcode is installed at $XCODE_APP but is not active. Run:" >&2
    echo "  sudo xcode-select -s $XCODE_APP/Contents/Developer" >&2
    echo "" >&2
    echo "Or for this session only:" >&2
    echo "  export DEVELOPER_DIR=$XCODE_APP/Contents/Developer" >&2
  else
    echo "Install Xcode from the Mac App Store, then run:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  fi
  exit 1
fi

export PATH="$(dirname "$xcodebuild_bin"):$PATH"

if [[ -z "${FASTLANE_USER:-}" ]]; then
  echo "Apple ID for TestFlight:"
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
