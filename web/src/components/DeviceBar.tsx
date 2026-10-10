import { useEffect, useState, type MouseEvent } from "react";
import { createPortal } from "react-dom";
import type { Device, Session, SessionSlot } from "../api";
import { isAppleTvDevice } from "../streamCompat";

type Props = {
  devices: Device[];
  selectedId: string | null;
  sessionsByDevice: Record<string, Session | undefined>;
  onSelect: (id: string) => void;
  onEdit: (id: string) => void;
  onCec: (id: string, action: string) => void;
  onStop: (sessionId: string) => void;
  onRefreshAudio: (sessionId: string) => Promise<Session>;
  onSetAudio: (sessionId: string, index: number) => Promise<Session>;
  onLaunch: (id: string) => Promise<void>;
  onAdd: () => void;
};

function slotPlayable(slot: SessionSlot | undefined): boolean {
  if (!slot) return false;
  return Boolean(slot.url || slot.channel_id || slot.youtube_url || slot.apituner_channel);
}

function canPickAudio(session: Session | undefined): boolean {
  if (!session || session.status !== "playing") return false;
  return session.slots.filter(slotPlayable).length > 1;
}

function layoutDims(layout: string): { rows: number; cols: number } {
  switch (layout) {
    case "2x1":
      return { rows: 1, cols: 2 };
    case "1x2":
      return { rows: 2, cols: 1 };
    case "2x2":
      return { rows: 2, cols: 2 };
    case "3x3":
      return { rows: 3, cols: 3 };
    default:
      return { rows: 1, cols: 1 };
  }
}

export default function DeviceBar({
  devices,
  selectedId,
  sessionsByDevice,
  onSelect,
  onEdit,
  onCec,
  onStop,
  onRefreshAudio,
  onSetAudio,
  onLaunch,
  onAdd,
}: Props) {
  const [launchingId, setLaunchingId] = useState<string | null>(null);
  const [launchNote, setLaunchNote] = useState<string | null>(null);
  const [picker, setPicker] = useState<Session | null>(null);
  const [pickerAnchor, setPickerAnchor] = useState<{ left: number; bottom: number; width: number } | null>(null);
  const [pickerError, setPickerError] = useState<string | null>(null);
  const [audioBusy, setAudioBusy] = useState(false);

  useEffect(() => {
    if (!picker) return;
    const live = Object.values(sessionsByDevice).find((session) => session?.id === picker.id);
    if (!live) setPicker(null);
  }, [picker, sessionsByDevice]);

  useEffect(() => {
    if (!picker) return;
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setPicker(null);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [picker]);

  async function openAudio(event: MouseEvent<HTMLButtonElement>, session: Session) {
    const rect = event.currentTarget.getBoundingClientRect();
    const { cols } = layoutDims(session.layout);
    const width = Math.min(280, Math.max(148, cols * 88));
    const left = Math.max(12, Math.min(rect.left, window.innerWidth - width - 12));
    setPickerAnchor({ left, bottom: window.innerHeight - rect.top + 8, width });
    setPicker(session);
    setPickerError(null);
    const openedId = session.id;
    try {
      const live = await onRefreshAudio(session.id);
      setPicker((current) => (current?.id === openedId ? live : current));
    } catch {
      // The stored session is enough to open the grid if the TV cannot be read.
    }
  }

  async function chooseAudio(index: number) {
    if (!picker || audioBusy) return;
    const slot = picker.slots[index];
    if (!slotPlayable(slot) || slot?.audio) return;
    setAudioBusy(true);
    setPickerError(null);
    try {
      const next = await onSetAudio(picker.id, index);
      setPicker(next);
    } catch (e) {
      setPickerError(e instanceof Error ? e.message : String(e));
    } finally {
      setAudioBusy(false);
    }
  }

  async function launch(device: Device) {
    setLaunchingId(device.id);
    setLaunchNote(null);
    try {
      await onLaunch(device.id);
      setLaunchNote(`Opened TVMaestro on ${device.name}`);
    } catch (e) {
      setLaunchNote(e instanceof Error ? e.message : String(e));
    } finally {
      setLaunchingId(null);
    }
  }

  return (
    <footer className="device-bar">
      {launchNote && (
        <span className="pill" title={launchNote} style={{ maxWidth: 280, overflow: "hidden", textOverflow: "ellipsis" }}>
          {launchNote}
        </span>
      )}
      {devices.length === 0 && (
        <span style={{ color: "var(--text-dim)", fontSize: "0.85rem" }}>
          No devices registered yet.
        </span>
      )}
      {devices.map((d) => {
        const session = sessionsByDevice[d.id];
        const cec = d.capabilities?.cec;
        const mvMax = d.capabilities?.multiview_max ?? 1;
        return (
          <div
            key={d.id}
            className={`device-chip ${selectedId === d.id ? "selected" : ""}`}
            onClick={() => onSelect(d.id)}
            onKeyDown={(e) => {
              if (e.key === "Enter") onSelect(d.id);
            }}
            role="button"
            tabIndex={0}
          >
            <span className={`device-dot ${d.online ? "on" : ""}`} />
            <strong>{d.name}</strong>
            <span style={{ color: "var(--text-faint)", fontSize: "0.75rem" }}>
              {d.host}:{d.port}
            </span>
            {mvMax <= 1 && (
              <span className="pill warn" title={d.capabilities?.chip_note || "Multiview not supported"}>
                single
              </span>
            )}
            {session && session.status === "error" && (
              <span className="pill warn" title={session.error || "Tune failed"}>
                error
              </span>
            )}
            {session && session.status !== "stopped" && session.status !== "error" && (
              <>
                <span className="pill">{session.layout}</span>
                {canPickAudio(session) && (
                  <button
                    type="button"
                    className="btn"
                    title="Choose which pane is audible"
                    onClick={(e) => {
                      e.stopPropagation();
                      void openAudio(e, session);
                    }}
                  >
                    Audio
                  </button>
                )}
                <button
                  type="button"
                  className="btn btn-danger"
                  onClick={(e) => {
                    e.stopPropagation();
                    onStop(session.id);
                  }}
                >
                  Stop
                </button>
              </>
            )}
            <button
              type="button"
              className="btn btn-ghost"
              title="Edit device"
              onClick={(e) => {
                e.stopPropagation();
                onEdit(d.id);
              }}
            >
              Edit
            </button>
            {isAppleTvDevice(d) && (
              <button
                type="button"
                className="btn"
                title="Open the TVMaestro app on this Apple TV"
                disabled={launchingId === d.id}
                onClick={(e) => {
                  e.stopPropagation();
                  void launch(d);
                }}
              >
                {launchingId === d.id ? "Opening…" : "Open"}
              </button>
            )}
            <div className="device-cec" onClick={(e) => e.stopPropagation()}>
              {cec?.power ? (
                <>
                  <button
                    type="button"
                    className="btn"
                    title={
                      isAppleTvDevice(d)
                        ? "Wake the Apple TV. The television follows only if Control TVs and Receivers is on."
                        : "Wake (Android TV Remote or adb) — TV follows via CEC"
                    }
                    onClick={() => onCec(d.id, "power_on")}
                  >
                    Wake
                  </button>
                  <button
                    type="button"
                    className="btn"
                    title={
                      isAppleTvDevice(d)
                        ? "Sleep the Apple TV. The television follows only if Control TVs and Receivers is on."
                        : "Sleep (Android TV Remote or adb) — TV follows via CEC"
                    }
                    onClick={() => onCec(d.id, "power_off")}
                  >
                    Sleep
                  </button>
                </>
              ) : null}
              <button
                type="button"
                className="btn"
                disabled={!cec?.volume}
                onClick={() => onCec(d.id, "volume_down")}
              >
                Vol−
              </button>
              <button
                type="button"
                className="btn"
                disabled={!cec?.volume}
                onClick={() => onCec(d.id, "volume_up")}
              >
                Vol+
              </button>
              <button
                type="button"
                className="btn"
                disabled={!cec?.mute}
                onClick={() => onCec(d.id, "mute")}
              >
                Mute
              </button>
            </div>
          </div>
        );
      })}
      <button type="button" className="btn" onClick={onAdd}>
        + Device
      </button>
      {picker && pickerAnchor &&
        createPortal(
          <AudioGrid
            session={picker}
            anchor={pickerAnchor}
            busy={audioBusy}
            error={pickerError}
            onChoose={(index) => void chooseAudio(index)}
            onClose={() => setPicker(null)}
          />,
          document.body,
        )}
    </footer>
  );
}

function AudioGrid({
  session,
  anchor,
  busy,
  error,
  onChoose,
  onClose,
}: {
  session: Session;
  anchor: { left: number; bottom: number; width: number };
  busy: boolean;
  error: string | null;
  onChoose: (index: number) => void;
  onClose: () => void;
}) {
  const { rows, cols } = layoutDims(session.layout);
  const count = rows * cols;
  return (
    <>
      <button type="button" className="audio-picker-backdrop" aria-label="Close audio picker" onClick={onClose} />
      <div
        className="audio-picker"
        style={{ left: anchor.left, bottom: anchor.bottom, width: anchor.width }}
        role="dialog"
        aria-label="Audio"
      >
        <div className="audio-picker-grid" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
          {Array.from({ length: count }, (_, index) => {
            const slot = session.slots[index];
            const playable = slotPlayable(slot);
            const audible = Boolean(playable && slot?.audio);
            const label = playable ? slot?.title || `Pane ${index + 1}` : "";
            return (
              <button
                key={index}
                type="button"
                className={`audio-cell${audible ? " on" : ""}`}
                disabled={!playable || busy}
                title={label || "Empty"}
                onClick={() => onChoose(index)}
              >
                {label}
              </button>
            );
          })}
        </div>
        {error && <div className="audio-picker-error">{error}</div>}
      </div>
    </>
  );
}
