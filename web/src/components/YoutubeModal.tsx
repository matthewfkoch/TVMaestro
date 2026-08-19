import { useEffect, useState } from "react";
import { api, type Device } from "../api";
import { youtubeCompatWarning } from "../streamCompat";

type Props = {
  open: boolean;
  devices: Device[];
  deviceId: string | null;
  onClose: () => void;
  onPlayed: () => void;
};

export default function YoutubeModal({ open, devices, deviceId, onClose, onPlayed }: Props) {
  const [url, setUrl] = useState("");
  const [title, setTitle] = useState("");
  const [selected, setSelected] = useState(deviceId || "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) return;
    setSelected(deviceId || "");
    setError(null);
  }, [open, deviceId]);

  if (!open) return null;

  const selectedDevice = devices.find((d) => d.id === selected) || null;
  const hlsWarning = youtubeCompatWarning(selectedDevice);

  async function play() {
    setBusy(true);
    setError(null);
    try {
      const slot = await api.resolveYoutube(url, title || undefined);
      if (!selected) throw new Error("Select a device");
      await api.createSession({
        device_id: selected,
        mode: "single",
        layout: "1",
        slots: [{ ...slot, audio: true }],
      });
      onPlayed();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-center">
      <div className="modal">
        <h2>Play via APITuner (YouTube)</h2>
        <p style={{ color: "var(--text-dim)", marginTop: 0 }}>
          Resolves a YouTube URL through APITuner’s encoder relay into an MPEG-TS stream. Android
          TV clients play this well; Apple TV generally needs HLS from Channels DVR.
        </p>
        <div style={{ display: "grid", gap: "0.75rem" }}>
          <div className="field">
            <label>YouTube URL</label>
            <input
              value={url}
              placeholder="https://www.youtube.com/watch?v=…"
              onChange={(e) => setUrl(e.target.value)}
            />
          </div>
          <div className="field">
            <label>Title (optional)</label>
            <input value={title} onChange={(e) => setTitle(e.target.value)} />
          </div>
          <div className="field">
            <label>Device</label>
            <select value={selected} onChange={(e) => setSelected(e.target.value)}>
              <option value="" disabled>
                Select…
              </option>
              {devices.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
            </select>
          </div>
        </div>
        {hlsWarning && (
          <div
            className="error"
            style={{
              marginTop: "0.75rem",
              background: "rgba(255, 180, 0, 0.12)",
              borderColor: "rgba(255, 180, 0, 0.35)",
              color: "var(--text)",
            }}
          >
            {hlsWarning}
          </div>
        )}
        {error && <div className="error" style={{ marginTop: "0.75rem" }}>{error}</div>}
        <div className="modal-actions">
          <button type="button" className="btn" onClick={onClose}>
            Cancel
          </button>
          <button
            type="button"
            className="btn btn-primary"
            disabled={!url || !selected || busy}
            onClick={play}
          >
            {busy ? "Resolving…" : "Play"}
          </button>
        </div>
      </div>
    </div>
  );
}
