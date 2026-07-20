# Apple TV client (stub)

Phase 4 placeholder for a future tvOS client that speaks the same control protocol as the Android TVMaestro app:

- Control API on a configurable port (Android default `9093`)
- `GET /api/health`, `GET /api/info`
- `POST /api/session`, `POST /api/session/stop`, `GET /api/session`
- `POST /api/cec` (power/volume/mute — map to tvOS / HomeKit where applicable)

Playback should use `AVPlayer` / `AVPlayerLayer` in a grid for multiview layouts `1`, `2x1`, `1x2`, `2x2`, with a single audio-focus slot.

No Swift sources are included in this milestone.
