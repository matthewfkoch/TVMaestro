# TVMaestro Android client

Kotlin Android TV app with Media3 ExoPlayer and an embedded control API on port **6791** by default.

## Build

```bash
# Ensure sdk.dir is set in local.properties (gitignored)
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Control API

| Method | Path | Body |
|--------|------|------|
| GET | `/api/health` | |
| GET | `/api/info` | capabilities + CEC flags |
| POST | `/api/session` | `{ id, mode, layout, slots:[{url,title,audio,channel_id}] }` |
| GET | `/api/session` | current session, including which slot has `audio` |
| POST | `/api/session/slot` | `{ index, audio_index, slot:{url,title,audio,channel_id} }` — replace one pane; other players stay up |
| POST | `/api/session/audio` | `{ index }` — move audio focus without restarting streams |
| POST | `/api/session/stop` | |
| POST | `/api/cec` | `{ action: power_on\|power_off\|volume_up\|volume_down\|mute }` |

Optional header: `X-Auth-Token` (set in on-device Settings).

## Multiview layouts

`1`, `2x1`, `1x2`, `2x2` — one ExoPlayer per slot; non-audio slots are muted.
