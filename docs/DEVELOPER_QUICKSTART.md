# Developer quickstart

This document is for contributors working on TVMaestro locally.

## Prerequisites

- Python 3.11+
- Node.js 18+
- Docker / Docker Compose
- Android Studio for Android builds
- Xcode 15+ for Apple TV builds

## Local backend

```bash
cd server
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt
TVMAESTRO_DATA_DIR=../data uvicorn tvmaestro.main:app --host 0.0.0.0 --port 6790 --reload
```

## Run tests

```bash
cd server
pytest -q
```

## Web UI

```bash
cd web
npm install
npm run dev
```

## Android app

```bash
cd android
./gradlew :app:assembleDebug
```

## Apple TV app

```bash
open appletv/TVMaestro.xcodeproj
```

## Docker workflow

```bash
docker compose up -d --build
```

## Helpful scripts

- `scripts/build-all.sh`
- `scripts/build-web.sh`
- `scripts/build-android.sh`
- `scripts/build-appletv.sh`
- `scripts/dev-server.sh`
