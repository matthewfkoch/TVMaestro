#!/usr/bin/env bash
# Bump the marketing version across all components (and increment Android versionCode).
# Usage: scripts/bump-version.sh 0.4.6
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NEW_VER="${1:-}"

if [[ ! "$NEW_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 X.Y.Z" >&2
  exit 1
fi

python3 - "$ROOT" "$NEW_VER" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
ver = sys.argv[2]

def sub_file(rel: str, pattern: str, repl: str) -> None:
    p = root / rel
    text = p.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, repl, text)
    if count == 0:
        raise SystemExit(f"Pattern not found in {rel}")
    p.write_text(updated, encoding="utf-8")

def bump_json(rel: str) -> None:
    p = root / rel
    data = json.loads(p.read_text(encoding="utf-8"))
    data["version"] = ver
    p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

sub_file("server/tvmaestro/__version__.py", r'__version__\s*=\s*"[^"]+"', f'__version__ = "{ver}"')
bump_json("web/package.json")
bump_json("mobile/package.json")

sub_file("android/app/build.gradle.kts", r'versionName\s*=\s*"[^"]+"', f'versionName = "{ver}"')
sub_file(
    "android/app/build.gradle.kts",
    r"(versionCode\s*=\s*)(\d+)",
    lambda m: f"{m.group(1)}{int(m.group(2)) + 1}",
)

sub_file("mobile/android/app/build.gradle", r'versionName\s+"[^"]+"', f'versionName "{ver}"')
sub_file(
    "mobile/android/app/build.gradle",
    r"(versionCode\s+)(\d+)",
    lambda m: f"{m.group(1)}{int(m.group(2)) + 1}",
)

sub_file("appletv/TVMaestro.xcodeproj/project.pbxproj", r"MARKETING_VERSION\s*=\s*[^;]+;", f"MARKETING_VERSION = {ver};")
sub_file("mobile/ios/App/App.xcodeproj/project.pbxproj", r"MARKETING_VERSION\s*=\s*[^;]+;", f"MARKETING_VERSION = {ver};")
sub_file("appletv/TVMaestro/ControlServer.swift", r'CFBundleShortVersionString"\] as\? String \?\? "[^"]+"', f'CFBundleShortVersionString"] as? String ?? "{ver}"')

print(f"Bumped all component versions to {ver} and incremented Android versionCode.")
PY
