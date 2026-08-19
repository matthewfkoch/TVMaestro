#!/usr/bin/env bash
# Interactive helper: store TestFlight secrets in GitHub and trigger the workflow.
#
# Usage:
#   scripts/setup-testflight-secrets.sh
#
# You need:
#   - gh CLI logged in (gh auth login)
#   - App Store Connect API key (.p8) from developer.apple.com
#   - Apple Team ID (10 chars)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="matthewfkoch/TVMaestro"

if ! command -v gh >/dev/null 2>&1; then
  echo "Install GitHub CLI: brew install gh && gh auth login" >&2
  exit 1
fi

echo "=== TVMaestro TestFlight setup ==="
echo "Repo: $REPO"
echo

read -r -p "Apple Team ID (10 chars, from developer.apple.com/account): " APPLE_TEAM_ID
read -r -p "ASC Key ID: " ASC_KEY_ID
read -r -p "ASC Issuer ID (UUID): " ASC_ISSUER_ID
read -r -p "Path to AuthKey_${ASC_KEY_ID}.p8: " P8_PATH

P8_PATH="${P8_PATH/#\~/$HOME}"
if [[ ! -f "$P8_PATH" ]]; then
  echo "File not found: $P8_PATH" >&2
  exit 1
fi

echo
echo "Setting GitHub secrets…"
gh secret set APPLE_TEAM_ID --repo "$REPO" --body "$APPLE_TEAM_ID"
gh secret set ASC_KEY_ID --repo "$REPO" --body "$ASC_KEY_ID"
gh secret set ASC_ISSUER_ID --repo "$REPO" --body "$ASC_ISSUER_ID"
gh secret set ASC_PRIVATE_KEY --repo "$REPO" < "$P8_PATH"

echo "Secrets saved."
echo
read -r -p "Trigger TestFlight workflow now? [Y/n] " TRIGGER
TRIGGER="${TRIGGER:-Y}"
if [[ "$TRIGGER" =~ ^[Yy] ]]; then
  gh workflow run "TestFlight (Apple TV).yml" --repo "$REPO"
  echo "Workflow started. Watch: https://github.com/$REPO/actions"
fi

echo
echo "On Apple TV: open TestFlight → install TVMaestro when processing completes."
echo "Local upload alternative: export vars and run scripts/testflight-appletv.sh"
