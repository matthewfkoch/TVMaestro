#!/usr/bin/env bash
# Build the phone/tablet companion: Android debug APK and iOS Simulator app.
# Does not sign, install, or prompt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mobile"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Capacitor 8 compiles Android sources as Java 21.
if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in \
    /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      break
    fi
  done
fi
if [[ -z "${JAVA_HOME:-}" || "$("$JAVA_HOME/bin/java" -version 2>&1)" != *"21."* ]]; then
  if ! /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java -version >/dev/null 2>&1; then
    NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew install openjdk@21
  fi
  export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
fi
export PATH="$JAVA_HOME/bin:$PATH"

SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}}"
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
if [[ ! -f android/local.properties ]]; then
  printf 'sdk.dir=%s\n' "$SDK_DIR" > android/local.properties
fi

PREPARE_IOS_ONLY=0
if [[ "${1:-}" == "--prepare-ios-only" ]]; then
  PREPARE_IOS_ONLY=1
fi

if [[ "$PREPARE_IOS_ONLY" == "0" ]]; then
npm install
npx cap sync

echo "Building Android debug APK"
(cd android && ./gradlew --no-daemon assembleDebug)
APK="$ROOT/mobile/android/app/build/outputs/apk/debug/app-debug.apk"
echo "Android APK: $APK"
fi

prepare_ios_capacitor() {
  # Xcode's Swift package downloader can sit forever on these binary frameworks.
  # Fetch them with curl and point CapApp-SPM at the local package instead.
  local dest="$ROOT/mobile/ios/capacitor-binaries"
  local version="8.5.3"
  mkdir -p "$dest"
  download_xcframework "Capacitor" "9316f568444411d362dcb4d1946e7572d4aef5d690c122ff6f1cb8a44a920c9f" "$version" "$dest"
  download_xcframework "Cordova" "bdcd8eab2d62a077efd76c3c8b9629e65ae7043c1462289a1e55de9be19bbf1f" "$version" "$dest"
  cat > "$dest/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "capacitor-binaries",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Capacitor", targets: ["Capacitor"]),
        .library(name: "Cordova", targets: ["Cordova"])
    ],
    targets: [
        .binaryTarget(name: "Capacitor", path: "Capacitor.xcframework"),
        .binaryTarget(name: "Cordova", path: "Cordova.xcframework")
    ]
)
EOF
  python3 - <<'PY'
import re
from pathlib import Path
path = Path("ios/App/CapApp-SPM/Package.swift")
text = path.read_text()
text = re.sub(
    r'\.package\(url: "https://github.com/ionic-team/capacitor-swift-pm\.git", exact: "[^"]+"\),?',
    '.package(name: "capacitor-binaries", path: "../../capacitor-binaries"),',
    text,
    count=1,
)
text = text.replace('package: "capacitor-swift-pm"', 'package: "capacitor-binaries"')
if "capacitor-swift-pm" in text:
    raise SystemExit("CapApp-SPM still references capacitor-swift-pm")
path.write_text(text)
PY
  rm -rf ios/DerivedData
  rm -f ios/App/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
}

download_xcframework() {
  local name="$1" checksum="$2" version="$3" dest="$4"
  if [[ -d "$dest/$name.xcframework" ]]; then
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  curl -fL --retry 3 -o "$tmp/$name.xcframework.zip" \
    "https://github.com/ionic-team/capacitor-swift-pm/releases/download/${version}/${name}.xcframework.zip"
  echo "${checksum}  $tmp/$name.xcframework.zip" | shasum -a 256 -c -
  unzip -q "$tmp/$name.xcframework.zip" -d "$dest"
  rm -rf "$tmp"
}

if [[ "$PREPARE_IOS_ONLY" == "1" ]]; then
  prepare_ios_capacitor
  exit 0
fi

if [[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Preparing iOS Capacitor frameworks"
  prepare_ios_capacitor
  echo "Building iOS Simulator app"
  xcodebuild \
    -project ios/App/App.xcodeproj \
    -scheme App \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$ROOT/mobile/ios/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
  echo "iOS Simulator build succeeded"
else
  echo "Xcode not found; skipped iOS Simulator build"
fi
