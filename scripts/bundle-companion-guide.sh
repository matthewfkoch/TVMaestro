#!/usr/bin/env bash
# Build the web guide into mobile/www/guide for the Capacitor companion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/web"
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi
TVMAESTRO_COMPANION=1 npm run build -- --base=/guide/
rm -rf "$ROOT/mobile/www/guide"
mkdir -p "$ROOT/mobile/www/guide"
cp -R dist/. "$ROOT/mobile/www/guide/"
echo "Companion guide: $ROOT/mobile/www/guide"
