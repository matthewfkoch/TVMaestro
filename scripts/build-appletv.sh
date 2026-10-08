#!/usr/bin/env bash
# Build the tvOS app for a generic Apple TV device, without signing.
# KSPlayer's binary includes a tvOS device slice and no tvOS simulator slice.
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

DESTINATION="${DESTINATION:-generic/platform=tvOS}"

mkdir -p "$DERIVED"
echo "Building $SCHEME ($CONFIG) → $DESTINATION"
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

APP=$(find "$DERIVED/Build/Products" -name 'TVMaestro.app' -type d | head -1 || true)
if [[ -n "${APP:-}" ]]; then
  echo "Apple TV app: $APP"
else
  echo "Build finished but TVMaestro.app was not produced under $DERIVED" >&2
  exit 1
fi
