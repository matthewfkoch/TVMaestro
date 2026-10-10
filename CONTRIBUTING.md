# Contributing

Thanks for your interest in improving TVMaestro.

## Ways to contribute

- report bugs
- propose features or improvements
- improve docs and troubleshooting guides
- test builds on Android TV / Apple TV / local Docker setups
- help review pull requests

## Repository layout

- `server/` — Python FastAPI backend and orchestration logic
- `web/` — React + Vite frontend
- `android/` — Android TV client
- `appletv/` — Apple TV / tvOS client
- `scripts/` — build and dev automation
- `docs/` — project documentation
- `.github/workflows/` — CI and release automation

## Development setup

### Server

```bash
cd server
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt
TVMAESTRO_DATA_DIR=../data uvicorn tvmaestro.main:app --host 0.0.0.0 --port 6790 --reload
```

Run tests:

```bash
cd server
pytest -q
```

### Web UI

```bash
cd web
npm install
npm run dev
```

### Android client

```bash
cd android
./gradlew :app:assembleDebug
```

### Apple TV client

Open the Xcode project:

```bash
open appletv/TVMaestro.xcodeproj
```

## Before you open a PR

- keep your change focused and easy to review
- update docs if behavior changes or new config is required
- validate the affected path with the smallest relevant command or test
- ensure the repository still builds for the relevant area

## Pull request expectations

Please include:

- a short summary of the change
- the reason for the change
- validation performed
- any follow-up work or open questions

## Code of conduct

Please be respectful and constructive. We expect contributors to engage in a professional, collaborative manner.

## Getting help

If you are unsure whether a change is appropriate, open a discussion or start with a targeted issue first.
