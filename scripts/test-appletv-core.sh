#!/usr/bin/env bash
# Compile and run pure-Swift unit tests for Apple TV core logic (TinyHTTPServer, SessionModels).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found; skipping Apple TV core tests" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tvmaestro-appletv-tests.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT/appletv/TVMaestro/SessionModels.swift" \
  "$ROOT/appletv/TVMaestro/TinyHTTPServer.swift" \
  "$ROOT/appletv/Tests/TVMaestroCoreTests.swift" \
  -o "$TMP_DIR/tests"

"$TMP_DIR/tests"
