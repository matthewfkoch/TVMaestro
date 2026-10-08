import { useEffect, useMemo, useRef, useState } from "react";
import type { Channel, Device, Programme } from "../api";
import ProgramArt from "./ProgramArt";

export type LayoutId = "1" | "2x1" | "1x2" | "2x2" | "3x3";

const CAPACITY: Record<LayoutId, number> = {
  "1": 1,
  "2x1": 2,
  "1x2": 2,
  "2x2": 4,
  "3x3": 9,
};

function currentByChannel(programmes: Programme[], now: number): Map<string, Programme> {
  const map = new Map<string, Programme>();
  for (const p of programmes) {
    if (p.start <= now && now < p.stop) map.set(p.channel_id, p);
  }
  return map;
}

function clockTime(ts: number): string {
  return new Date(ts * 1000).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function SlotChannelPicker({
  channels,
  onNow,
  channel,
  onChange,
}: {
  channels: Channel[];
  onNow: Map<string, Programme>;
  channel: Channel | null;
  onChange: (channel: Channel | null) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const rootRef = useRef<HTMLDivElement>(null);
  const playing = channel ? onNow.get(channel.id) : undefined;

  useEffect(() => {
    if (!open) return;
    const onPointer = (event: MouseEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return channels;
    return channels.filter((c) => {
      const show = onNow.get(c.id)?.title || "";
      return `${c.number || ""} ${c.name} ${show}`.toLowerCase().includes(needle);
    });
  }, [channels, onNow, query]);

  return (
    <div className="channel-picker" ref={rootRef}>
      <button
        type="button"
        className={`channel-picker-btn${channel ? "" : " empty"}`}
        aria-expanded={open}
        onClick={() => {
          setQuery("");
          setOpen((value) => !value);
        }}
      >
        {playing?.icon && (
          <ProgramArt src={playing.icon} width={120} height={90} className="channel-art" />
        )}
        <span className="channel-picker-copy">
          <span className="channel-picker-name">
            {channel ? `${channel.number ? `${channel.number} ` : ""}${channel.name}` : "Empty slot…"}
          </span>
          {playing && (
            <span className="channel-picker-show">
              {playing.title}
              {playing.subtitle ? ` · ${playing.subtitle}` : ""}
              {` · ${clockTime(playing.start)}–${clockTime(playing.stop)}`}
            </span>
          )}
        </span>
      </button>
      {open && (
        <div className="channel-picker-menu">
          <input
            autoFocus
            value={query}
            placeholder="Search channels or shows"
            onChange={(e) => setQuery(e.target.value)}
          />
          <div className="channel-picker-list">
            <button
              type="button"
              className="channel-option"
              onClick={() => {
                onChange(null);
                setOpen(false);
              }}
            >
              <span className="channel-option-copy">Empty slot…</span>
            </button>
            {filtered.map((c) => {
              const prog = onNow.get(c.id);
              return (
                <button
                  key={c.id}
                  type="button"
                  className={`channel-option${c.id === channel?.id ? " selected" : ""}`}
                  onClick={() => {
                    onChange(c);
                    setOpen(false);
                  }}
                >
                  <ProgramArt
                    src={prog?.icon}
                    width={120}
                    height={90}
                    className="channel-art"
                    fallback
                  />
                  <span className="channel-option-copy">
                    <span className="channel-option-name">
                      {c.number ? `${c.number} ` : ""}
                      {c.name}
                    </span>
                    {prog && <span className="channel-option-show">{prog.title}</span>}
                  </span>
                </button>
              );
            })}
            {filtered.length === 0 && <div className="channel-option-empty">No matches</div>}
          </div>
        </div>
      )}
    </div>
  );
}

type Props = {
  channels: Channel[];
  programmes: Programme[];
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
  programmes,
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
  const [now, setNow] = useState(() => Date.now() / 1000);
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now() / 1000), 30_000);
    return () => window.clearInterval(id);
  }, []);
  const onNow = useMemo(() => currentByChannel(programmes, now), [programmes, now]);

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
                    <SlotChannelPicker
                      channels={channels}
                      onNow={onNow}
                      channel={ch}
                      onChange={(next) => onSetSlot(i, next)}
                    />
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
