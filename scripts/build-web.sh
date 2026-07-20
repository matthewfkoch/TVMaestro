#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:${PATH}"
cd "$ROOT/web"
npm install
npm run build
mkdir -p "$ROOT/server/tvmaestro/web"
rm -rf "$ROOT/server/tvmaestro/web/assets" "$ROOT/server/tvmaestro/web/index.html"
cp -R "$ROOT/web/dist/." "$ROOT/server/tvmaestro/web/"
echo "Web UI copied to server/tvmaestro/web"
