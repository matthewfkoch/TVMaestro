#!/usr/bin/env bash
# Build the Android TV debug APK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/android"

if [[ ! -x ./gradlew ]]; then
  chmod +x ./gradlew
fi

./gradlew --no-daemon :app:assembleDebug "$@"
APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
echo "Android APK: $APK"
