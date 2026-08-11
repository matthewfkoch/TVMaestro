#!/usr/bin/env bash
# Build the tvOS app for the Apple TV simulator (no device signing required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/appletv/TVMaestro.xcodeproj"
SCHEME="TVMaestro"
CONFIG="${CONFIGURATION:-Debug}"
DERIVED="${DERIVED_DATA_PATH:-$ROOT/appletv/build}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode from the App Store, then:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is pointing at Command Line Tools only. Switch to full Xcode:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

DESTINATION="${DESTINATION:-platform=tvOS Simulator,name=Apple TV}"

mkdir -p "$DERIVED"
echo "Building $SCHEME ($CONFIG) → $DESTINATION"
set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "Retrying with generic tvOS Simulator destination…"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=tvOS Simulator' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build
fi

APP=$(find "$DERIVED/Build/Products" -name 'TVMaestro.app' -type d | head -1 || true)
if [[ -n "${APP:-}" ]]; then
  echo "Apple TV app: $APP"
else
  echo "Build finished (check DerivedData under $DERIVED)"
fi
