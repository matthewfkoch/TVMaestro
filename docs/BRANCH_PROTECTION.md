# Branch protection guidance

Use branch protection on `main` to keep the repo stable and make sure CI and release workflows are not bypassed.

## Recommended settings

In GitHub, go to:

- `Settings` → `Branches` → `Add branch protection rule`

Configure the `main` branch with:

- Require a pull request before merging
- Require status checks to pass before merging
- Require branches to be up to date before merging
- Require approvals (at least 1 review is a good starting point)
- Dismiss stale pull request approvals when new commits are pushed
- Include administrators in this rule

## Required status checks

At minimum, enable checks from the CI workflow that validate the server and web build paths.

If your Apple TV and Android builds are part of CI, those checks should also be required when they are available.

## Why this matters

This repo includes:

- automated Python tests
- web build validation
- Docker image validation
- Android debug APK build validation
- Apple TV build validation in CI
- release automation for container + APK publishing

Branch protection helps ensure those checks are not skipped during normal development.

## Solo-maintainer note

Even for a single-maintainer repo, protection is still useful because it prevents accidental direct pushes, keeps validation visible, and makes the release flow more reliable.

## Optional settings

These are useful later, but not strictly required:

- Require conversation resolution before merging
- Require signed commits
- Require CODEOWNERS review if the repo grows and multiple contributors are added
