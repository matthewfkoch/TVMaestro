#!/usr/bin/env bash
# Check version consistency across server, web, Android TV, Apple TV, and mobile companion.
# Usage:
#   scripts/check-versions.sh               # print all component versions (exit 0)
#   scripts/check-versions.sh --strict      # fail if any component version differs
#   scripts/check-versions.sh --tag v0.4.5  # fail if any component != 0.4.5
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STRICT=0
EXPECTED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --tag)
      EXPECTED="${2:-}"
      EXPECTED="${EXPECTED#v}"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

python3 - "$ROOT" "$STRICT" "$EXPECTED" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
strict = sys.argv[2] == "1"
expected = sys.argv[3].strip()

def read_regex(rel: str, pattern: str) -> str:
    text = (root / rel).read_text(encoding="utf-8")
    matches = sorted(set(re.findall(pattern, text)))
    if not matches:
        return "MISSING"
    if len(matches) > 1:
        return f"MIXED({','.join(matches)})"
    return matches[0]

versions = {
    "server": read_regex("server/tvmaestro/__version__.py", r'__version__\s*=\s*"([^"]+)"'),
    "web": json.loads((root / "web/package.json").read_text(encoding="utf-8")).get("version", "MISSING"),
    "mobile": json.loads((root / "mobile/package.json").read_text(encoding="utf-8")).get("version", "MISSING"),
    "android-tv": read_regex("android/app/build.gradle.kts", r'versionName\s*=\s*"([^"]+)"'),
    "companion-android": read_regex("mobile/android/app/build.gradle", r'versionName\s+"([^"]+)"'),
    "appletv": read_regex("appletv/TVMaestro.xcodeproj/project.pbxproj", r"MARKETING_VERSION\s*=\s*([^;]+);"),
    "companion-ios": read_regex("mobile/ios/App/App.xcodeproj/project.pbxproj", r"MARKETING_VERSION\s*=\s*([^;]+);"),
}

for name, ver in versions.items():
    print(f"{name:20s} {ver}")

unique = set(versions.values())
if expected:
    mismatches = {k: v for k, v in versions.items() if v != expected}
    if mismatches:
        print(f"\nVersion mismatch for expected {expected}: {mismatches}", file=sys.stderr)
        sys.exit(1)
elif strict and len(unique) != 1:
    print(f"\nComponent versions are out of sync: {sorted(unique)}", file=sys.stderr)
    sys.exit(1)
PY
