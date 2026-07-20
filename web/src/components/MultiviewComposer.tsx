import type { Channel, Device } from "../api";

export type LayoutId = "1" | "2x1" | "1x2" | "2x2";

const CAPACITY: Record<LayoutId, number> = {
  "1": 1,
  "2x1": 2,
  "1x2": 2,
  "2x2": 4,
};

type Props = {
  channels: Channel[];
  devices: Device[];
  deviceId: string | null;
  layout: LayoutId;
  slots: Array<Channel | null>;
  audioIndex: number;
  onLayout: (layout: LayoutId) => void;
  onDevice: (id: string) => void;
  onSetSlot: (index: number, channel: Channel | null) => void;
  onAudio: (index: number) => void;
  onSend: () => void;
  onClose: () => void;
  busy: boolean;
  error?: string | null;
};

export default function MultiviewComposer({
  channels,
  devices,
  deviceId,
  layout,
  slots,
  audioIndex,
  onLayout,
  onDevice,
  onSetSlot,
  onAudio,
  onSend,
  onClose,
  busy,
  error,
}: Props) {
  const selected = devices.find((d) => d.id === deviceId);
  const deviceMax = selected?.capabilities?.multiview_max ?? 1;
  const allowedLayouts = (Object.keys(CAPACITY) as LayoutId[]).filter(
    (id) => CAPACITY[id] <= deviceMax,
  );
  const effectiveLayout = allowedLayouts.includes(layout) ? layout : allowedLayouts[0] || "1";
  const cap = Math.min(CAPACITY[effectiveLayout], deviceMax);
  const filled = slots.slice(0, cap).filter(Boolean).length;

  return (
    <>
      <button type="button" className="sheet-backdrop" aria-label="Close" onClick={onClose} />
      <aside className="sheet">
        <header>
          <div>
            <h2>Multiview</h2>
            <p>
              {deviceMax <= 1
                ? selected?.capabilities?.chip_note ||
                  "This device does not support multiview."
                : `Choose a layout, then assign up to ${cap} streams.`}
            </p>
          </div>
          <button type="button" className="btn btn-ghost" onClick={onClose}>
            Close
          </button>
        </header>
        <div className="sheet-body">
          <div className="field">
            <label>Device</label>
            <select value={deviceId || ""} onChange={(e) => onDevice(e.target.value)}>
              <option value="" disabled>
                Select a device…
              </option>
              {devices.map((d) => (
                <option key={d.id} value={d.id} disabled={(d.capabilities?.multiview_max ?? 1) <= 1}>
                  {d.name} {d.online ? "●" : "○"}
                  {(d.capabilities?.multiview_max ?? 1) <= 1 ? " (no multiview)" : ""}
                </option>
              ))}
            </select>
          </div>

          {deviceMax > 1 && (
          <div className="field">
            <label>Layout</label>
            <div className="layout-grid">
              {allowedLayouts.map((id) => (
                <button
                  key={id}
                  type="button"
                  className={`layout-card l${id} ${effectiveLayout === id ? "selected" : ""}`}
                  onClick={() => onLayout(id)}
                  title={id}
                >
                  {Array.from({ length: CAPACITY[id] }).map((_, i) => (
                    <span key={i} />
                  ))}
                </button>
              ))}
            </div>
          </div>
          )}

          {deviceMax > 1 && (
          <div className="field">
            <label>Slots</label>
            <div className="slot-list">
              {Array.from({ length: cap }).map((_, i) => {
                const ch = slots[i];
                return (
                  <div className={`slot-row ${ch ? "" : "empty"}`} key={i}>
                    <button
                      type="button"
                      className="btn"
                      title="Audio focus"
                      onClick={() => onAudio(i)}
                      style={{
                        borderColor: audioIndex === i ? "var(--accent)" : undefined,
                        color: audioIndex === i ? "var(--accent)" : undefined,
                      }}
                    >
                      ♪
                    </button>
                    <select
                      value={ch?.id || ""}
                      onChange={(e) => {
                        const next = channels.find((c) => c.id === e.target.value) || null;
                        onSetSlot(i, next);
                      }}
                    >
                      <option value="">Empty slot…</option>
                      {channels.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.number ? `${c.number} ` : ""}
                          {c.name}
                        </option>
                      ))}
                    </select>
                    <button type="button" className="btn btn-ghost" onClick={() => onSetSlot(i, null)}>
                      Clear
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
          )}

          {error && <div className="error">{error}</div>}
        </div>
        <div className="sheet-footer">
          <button
            type="button"
            className="btn btn-primary"
            disabled={!deviceId || filled < 1 || busy || deviceMax <= 1}
            onClick={onSend}
          >
            {busy ? "Sending…" : `Send ${filled} stream${filled === 1 ? "" : "s"}`}
          </button>
        </div>
      </aside>
    </>
  );
}

export { CAPACITY };
