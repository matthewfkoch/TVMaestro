import type { Channel, Device, Programme } from "../api";

type Props = {
  channel: Channel;
  programme?: Programme | null;
  devices: Device[];
  selectedDeviceId: string | null;
  onSelectDevice: (id: string) => void;
  onPlay: () => void;
  onMultiview: () => void;
  onYoutube: () => void;
  onClose: () => void;
  busy: boolean;
  error?: string | null;
};

export default function TuneSheet({
  channel,
  programme,
  devices,
  selectedDeviceId,
  onSelectDevice,
  onPlay,
  onMultiview,
  onYoutube,
  onClose,
  busy,
  error,
}: Props) {
  const selected = devices.find((d) => d.id === selectedDeviceId);
  const canMultiview = (selected?.capabilities?.multiview_max ?? 1) > 1;

  return (
    <>
      <button type="button" className="sheet-backdrop" aria-label="Close" onClick={onClose} />
      <aside className="sheet">
        <header>
          <div>
            <h2>{programme?.title || channel.name}</h2>
            <p>
              {channel.number ? `${channel.number} · ` : ""}
              {channel.name}
              {programme?.subtitle ? ` · ${programme.subtitle}` : ""}
            </p>
          </div>
          <button type="button" className="btn btn-ghost" onClick={onClose}>
            Close
          </button>
        </header>
        <div className="sheet-body">
          {programme?.description && <p style={{ margin: 0, color: "var(--text-dim)" }}>{programme.description}</p>}

          <div className="field">
            <label>Target device</label>
            <select
              value={selectedDeviceId || ""}
              onChange={(e) => onSelectDevice(e.target.value)}
            >
              <option value="" disabled>
                Select a device…
              </option>
              {devices.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name} {d.online ? "●" : "○"} ({d.host})
                  {(d.capabilities?.multiview_max ?? 1) > 1 ? "" : " · single only"}
                </option>
              ))}
            </select>
          </div>

          {selected && !canMultiview && selected.capabilities?.chip_note && (
            <p style={{ margin: 0, color: "var(--text-dim)", fontSize: "0.85rem" }}>
              {selected.capabilities.chip_note}
            </p>
          )}

          {error && <div className="error">{error}</div>}
        </div>
        <div className="sheet-footer">
          <button type="button" className="btn" onClick={onYoutube}>
            YouTube…
          </button>
          <button
            type="button"
            className="btn"
            onClick={onMultiview}
            disabled={!selectedDeviceId || !canMultiview}
            title={canMultiview ? "Multiview" : "Selected device does not support multiview"}
          >
            Multiview
          </button>
          <button
            type="button"
            className="btn btn-primary"
            onClick={onPlay}
            disabled={!selectedDeviceId || busy}
          >
            {busy ? "Tuning…" : "Play"}
          </button>
        </div>
      </aside>
    </>
  );
}
