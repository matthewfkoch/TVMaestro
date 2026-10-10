#!/usr/bin/env bash
# Archive the iPhone/iPad companion and upload it to TestFlight.
# Uses the same Apple credentials as the Apple TV upload (appletv/.env).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
if [[ -z "${FASTLANE_PASSWORD:-}" && -n "${FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD:-}" ]]; then
  export FASTLANE_PASSWORD="$FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD"
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -x /opt/homebrew/opt/ruby@3.4/bin/bundle ]]; then
  export PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH"
elif [[ -x /opt/homebrew/opt/ruby/bin/bundle ]]; then
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
fi
export PATH="${DEVELOPER_DIR}/usr/bin:$PATH"

"$ROOT/scripts/build-mobile.sh" --prepare-ios-only
# codesign rejects resource forks and Finder info copied into the app bundle.
xattr -cr "$ROOT/mobile/ios" "$ROOT/mobile/www" || true

if ! command -v bundle >/dev/null 2>&1; then
  echo "Install bundler: gem install bundler" >&2
  exit 1
fi

cd "$ROOT/appletv"
bundle config set --local path 'vendor/bundle'
bundle install --quiet

cd "$ROOT/mobile"
echo "Building and uploading the iOS companion to TestFlight…"
BUNDLE_GEMFILE="$ROOT/appletv/Gemfile" bundle exec fastlane ios beta "$@"
