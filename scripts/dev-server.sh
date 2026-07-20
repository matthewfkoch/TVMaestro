#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/server"
# shellcheck disable=SC1091
source .venv/bin/activate
export TVMAESTRO_DATA_DIR="${TVMAESTRO_DATA_DIR:-$ROOT/data}"
exec uvicorn tvmaestro.main:app --host 0.0.0.0 --port "${TVMAESTRO_PORT:-6790}" --reload
