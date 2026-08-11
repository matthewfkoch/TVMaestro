#!/usr/bin/env bash
# Run server tests + build web, Docker image, Android APK, and (optionally) Apple TV.
#
# Usage:
#   scripts/build-all.sh              # everything available on this machine
#   scripts/build-all.sh --skip-docker
#   scripts/build-all.sh --skip-android
#   scripts/build-all.sh --skip-appletv
#   scripts/build-all.sh --only server,web
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_DOCKER=0
SKIP_ANDROID=0
SKIP_APPLETV=0
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-android) SKIP_ANDROID=1 ;;
    --skip-appletv) SKIP_APPLETV=1 ;;
    --only) ONLY="${2:-}"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

want() {
  local name="$1"
  if [[ -n "$ONLY" ]]; then
    [[ ",$ONLY," == *",$name,"* ]]
  else
    return 0
  fi
}

section() {
  echo
  echo "=== $* ==="
}

FAILED=()
run_step() {
  local name="$1"
  shift
  if ! want "$name"; then
    echo "skip $name (--only)"
    return 0
  fi
  section "$name"
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name" >&2
    FAILED+=("$name")
  fi
}

run_step server bash -c '
  set -euo pipefail
  cd "'"$ROOT"'/server"
  if [[ -d .venv ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
  fi
  if ! pip install -q -r requirements-dev.txt; then
    echo "warning: pip install failed (need Python 3.11+ for androidtvremote2); using existing env" >&2
  fi
  pytest -q
'

run_step web "$ROOT/scripts/build-web.sh"

if [[ $SKIP_DOCKER -eq 0 ]]; then
  run_step docker bash -c '
    if ! command -v docker >/dev/null 2>&1; then
      echo "docker not installed — skip"
      exit 0
    fi
    docker build -f server/Dockerfile -t tvmaestro:local "'"$ROOT"'"
  '
else
  echo "skip docker (--skip-docker)"
fi

if [[ $SKIP_ANDROID -eq 0 ]]; then
  if want android; then
    if command -v java >/dev/null 2>&1 || [[ -x "$ROOT/android/gradlew" ]]; then
      run_step android "$ROOT/scripts/build-android.sh"
    else
      echo "skip android (no Java / Android SDK toolchain)"
    fi
  fi
else
  echo "skip android (--skip-android)"
fi

if [[ $SKIP_APPLETV -eq 0 ]]; then
  if want appletv; then
    if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
      run_step appletv "$ROOT/scripts/build-appletv.sh"
    else
      echo "skip appletv (full Xcode required — install Xcode or use CI macos runner)"
    fi
  fi
else
  echo "skip appletv (--skip-appletv)"
fi

echo
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Failed steps: ${FAILED[*]}" >&2
  exit 1
fi
echo "All requested builds succeeded."
