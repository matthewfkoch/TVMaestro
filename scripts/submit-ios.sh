#!/usr/bin/env bash
# Upload the iOS companion listing, screenshots, Release IPA, and submit for review.
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
# Fall back to Apple ID login when the API key file is missing.
if [[ -n "${ASC_API_KEY_PATH:-}" && ! -f "${ASC_API_KEY_PATH}" ]]; then
  echo "ASC_API_KEY_PATH is set but the file is missing; using FASTLANE_USER instead."
  unset ASC_API_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
fi

# Reuse Apple TV review contact when the companion files are missing.
for name in first_name.txt last_name.txt phone_number.txt email_address.txt; do
  dest="$ROOT/mobile/fastlane/metadata/review_information/$name"
  src="$ROOT/appletv/fastlane/metadata/review_information/$name"
  if [[ ! -s "$dest" && -s "$src" ]]; then
    cp "$src" "$dest"
    echo "Copied review contact $name from the Apple TV listing"
  fi
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -x /opt/homebrew/opt/ruby@3.3/bin/bundle ]]; then
  export PATH="/opt/homebrew/opt/ruby@3.3/bin:$PATH"
elif [[ -x /opt/homebrew/opt/ruby@3.4/bin/bundle ]]; then
  export PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH"
elif [[ -x /opt/homebrew/opt/ruby/bin/bundle ]]; then
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
fi
export PATH="${DEVELOPER_DIR}/usr/bin:$PATH"

"$ROOT/scripts/bundle-companion-guide.sh"
"$ROOT/scripts/build-mobile.sh" --prepare-ios-only
cd "$ROOT/mobile"
npx cap sync ios
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
echo "Uploading listing, screenshots, and Release IPA, then submitting for review…"
BUNDLE_GEMFILE="$ROOT/appletv/Gemfile" bundle exec fastlane ios submit "$@"
