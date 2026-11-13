import { useEffect, useMemo, useState, type MouseEvent } from "react";
import { createPortal } from "react-dom";
import type { Channel, Device, Programme, Session, SessionSlot } from "../api";
import { isAppleTvDevice } from "../streamCompat";
import ProgramArt from "./ProgramArt";

type Props = {
  devices: Device[];
  selectedId: string | null;
  sessionsByDevice: Record<string, Session | undefined>;
  channels: Channel[];
  programmes: Programme[];
  onSelect: (id: string) => void;
  onEdit: (id: string) => void;
  onCec: (id: string, action: string) => void;
  onStop: (sessionId: string) => void;
  onRefreshAudio: (sessionId: string) => Promise<Session>;
  onSetAudio: (sessionId: string, index: number) => Promise<Session>;
  onReplaceSlot: (sessionId: string, index: number, channelId: string | null) => Promise<Session>;
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

function canChangeChannel(session: Session | undefined): boolean {
  if (!session || session.status !== "playing") return false;
  const { rows, cols } = layoutDims(session.layout);
  return rows * cols > 1;
}

function currentByChannel(programmes: Programme[], now: number): Map<string, Programme> {
  const map = new Map<string, Programme>();
  for (const programme of programmes) {
    if (programme.start <= now && now < programme.stop) map.set(programme.channel_id, programme);
  }
  return map;
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
  channels,
  programmes,
  onSelect,
  onEdit,
  onCec,
  onStop,
  onRefreshAudio,
  onSetAudio,
  onReplaceSlot,
  onLaunch,
  onAdd,
}: Props) {
  const [launchingId, setLaunchingId] = useState<string | null>(null);
  const [launchNote, setLaunchNote] = useState<string | null>(null);
  const [picker, setPicker] = useState<Session | null>(null);
  const [pickerAnchor, setPickerAnchor] = useState<{ left: number; bottom: number; width: number } | null>(null);
  const [pickerError, setPickerError] = useState<string | null>(null);
  const [audioBusy, setAudioBusy] = useState(false);
  const [changePicker, setChangePicker] = useState<Session | null>(null);
  const [changeAnchor, setChangeAnchor] = useState<{ left: number; bottom: number; width: number } | null>(null);
  const [changeIndex, setChangeIndex] = useState(0);
  const [changeQuery, setChangeQuery] = useState("");
  const [changeError, setChangeError] = useState<string | null>(null);
  const [changeBusy, setChangeBusy] = useState(false);
  const [controlsId, setControlsId] = useState<string | null>(null);
  const [controlsAnchor, setControlsAnchor] = useState<{ left: number; bottom: number; width: number } | null>(null);

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

  useEffect(() => {
    if (!changePicker) return;
    const live = Object.values(sessionsByDevice).find((session) => session?.id === changePicker.id);
    if (!live || live.status !== "playing") setChangePicker(null);
    else if (live !== changePicker) setChangePicker(live);
  }, [changePicker, sessionsByDevice]);

  useEffect(() => {
    if (!changePicker) return;
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setChangePicker(null);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [changePicker]);

  useEffect(() => {
    setPicker(null);
    setChangePicker(null);
    setControlsId(null);
  }, [selectedId]);

  useEffect(() => {
    if (!controlsId) return;
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setControlsId(null);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [controlsId]);

  function openChange(event: MouseEvent<HTMLButtonElement>, session: Session) {
    const rect = event.currentTarget.getBoundingClientRect();
    const width = Math.min(340, window.innerWidth - 24);
    const left = Math.max(12, Math.min(rect.left, window.innerWidth - width - 12));
    const first = session.slots.findIndex(slotPlayable);
    setPicker(null);
    setControlsId(null);
    setChangeAnchor({ left, bottom: window.innerHeight - rect.top + 8, width });
    setChangeIndex(first >= 0 ? first : 0);
    setChangeQuery("");
    setChangeError(null);
    setChangePicker(session);
  }

  async function chooseChannel(channel: Channel | null) {
    if (!changePicker || changeBusy) return;
    const slot = changePicker.slots[changeIndex];
    if (channel && (slot?.channel_id === channel.id || (slot?.url && slot.url === channel.url))) return;
    const playable = changePicker.slots.filter(slotPlayable).length;
    if (!channel && playable <= 1 && slotPlayable(slot)) return;
    setChangeBusy(true);
    setChangeError(null);
    try {
      const next = await onReplaceSlot(changePicker.id, changeIndex, channel?.id ?? null);
      setChangePicker(next);
    } catch (e) {
      setChangeError(e instanceof Error ? e.message : String(e));
    } finally {
      setChangeBusy(false);
    }
  }

  function openControls(event: MouseEvent<HTMLButtonElement>, device: Device) {
    setPicker(null);
    setChangePicker(null);
    const rect = event.currentTarget.getBoundingClientRect();
    const width = Math.min(260, window.innerWidth - 24);
    const left = Math.max(12, Math.min(rect.left, window.innerWidth - width - 12));
    setControlsAnchor({ left, bottom: window.innerHeight - rect.top + 8, width });
    setControlsId(device.id);
  }

  async function openAudio(event: MouseEvent<HTMLButtonElement>, session: Session) {
    setChangePicker(null);
    setControlsId(null);
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

  const controlsDevice = controlsId ? devices.find((device) => device.id === controlsId) : undefined;
  const playing = (session: Session | undefined) =>
    Boolean(session && session.status !== "stopped" && session.status !== "error");

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
        const mvMax = d.capabilities?.multiview_max ?? 1;
        const selected = selectedId === d.id;
        const live = playing(session);
        return (
          <div
            key={d.id}
            className={`device-chip ${selected ? "selected" : ""}`}
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
            {live && session && <span className="pill">{session.layout}</span>}
            {selected && (
              <>
                {live && session && (
                  <>
                    {canChangeChannel(session) && (
                      <button
                        type="button"
                        className="btn"
                        title="Change one pane to a different channel"
                        onClick={(e) => {
                          e.stopPropagation();
                          openChange(e, session);
                        }}
                      >
                        Change
                      </button>
                    )}
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
                <button
                  type="button"
                  className="btn"
                  title="Power and volume"
                  onClick={(e) => {
                    e.stopPropagation();
                    openControls(e, d);
                  }}
                >
                  Controls
                </button>
              </>
            )}
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
      {changePicker && changeAnchor &&
        createPortal(
          <ChangeGrid
            session={changePicker}
            anchor={changeAnchor}
            selected={changeIndex}
            query={changeQuery}
            channels={channels}
            programmes={programmes}
            busy={changeBusy}
            error={changeError}
            onSelectPane={setChangeIndex}
            onQuery={setChangeQuery}
            onChoose={(channel) => void chooseChannel(channel)}
            onClose={() => setChangePicker(null)}
          />,
          document.body,
        )}
      {controlsDevice && controlsAnchor &&
        createPortal(
          <ControlsPanel
            device={controlsDevice}
            anchor={controlsAnchor}
            onCec={(action) => onCec(controlsDevice.id, action)}
            onClose={() => setControlsId(null)}
          />,
          document.body,
        )}
    </footer>
  );
}

function ControlsPanel({
  device,
  anchor,
  onCec,
  onClose,
}: {
  device: Device;
  anchor: { left: number; bottom: number; width: number };
  onCec: (action: string) => void;
  onClose: () => void;
}) {
  const cec = device.capabilities?.cec;
  const apple = isAppleTvDevice(device);
  return (
    <>
      <button type="button" className="audio-picker-backdrop" aria-label="Close controls" onClick={onClose} />
      <div
        className="audio-picker controls-picker"
        style={{ left: anchor.left, bottom: anchor.bottom, width: anchor.width }}
        role="dialog"
        aria-label="Controls"
      >
        {cec?.power && (
          <div className="controls-row">
            <button
              type="button"
              className="btn"
              title={
                apple
                  ? "Wake the Apple TV. The television follows only if Control TVs and Receivers is on."
                  : "Wake (Android TV Remote or adb) — TV follows via CEC"
              }
              onClick={() => onCec("power_on")}
            >
              Wake
            </button>
            <button
              type="button"
              className="btn"
              title={
                apple
                  ? "Sleep the Apple TV. The television follows only if Control TVs and Receivers is on."
                  : "Sleep (Android TV Remote or adb) — TV follows via CEC"
              }
              onClick={() => onCec("power_off")}
            >
              Sleep
            </button>
          </div>
        )}
        <div className="controls-row">
          <button type="button" className="btn" disabled={!cec?.volume} onClick={() => onCec("volume_down")}>
            Vol−
          </button>
          <button type="button" className="btn" disabled={!cec?.volume} onClick={() => onCec("volume_up")}>
            Vol+
          </button>
          <button type="button" className="btn" disabled={!cec?.mute} onClick={() => onCec("mute")}>
            Mute
          </button>
        </div>
      </div>
    </>
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

function ChangeGrid({
  session,
  anchor,
  selected,
  query,
  channels,
  programmes,
  busy,
  error,
  onSelectPane,
  onQuery,
  onChoose,
  onClose,
}: {
  session: Session;
  anchor: { left: number; bottom: number; width: number };
  selected: number;
  query: string;
  channels: Channel[];
  programmes: Programme[];
  busy: boolean;
  error: string | null;
  onSelectPane: (index: number) => void;
  onQuery: (query: string) => void;
  onChoose: (channel: Channel | null) => void;
  onClose: () => void;
}) {
  const { rows, cols } = layoutDims(session.layout);
  const count = rows * cols;
  const now = Date.now() / 1000;
  const onNow = useMemo(() => currentByChannel(programmes, now), [programmes, now]);
  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return channels;
    return channels.filter((channel) => {
      const show = onNow.get(channel.id)?.title || "";
      return `${channel.number || ""} ${channel.name} ${show}`.toLowerCase().includes(needle);
    });
  }, [channels, onNow, query]);
  const playableCount = session.slots.filter(slotPlayable).length;
  const selectedSlot = session.slots[selected];
  const canClear = slotPlayable(selectedSlot) && playableCount > 1;

  return (
    <>
      <button type="button" className="audio-picker-backdrop" aria-label="Close channel changer" onClick={onClose} />
      <div
        className="audio-picker change-picker"
        style={{ left: anchor.left, bottom: anchor.bottom, width: anchor.width }}
        role="dialog"
        aria-label="Change channel"
      >
        <div className="audio-picker-grid" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
          {Array.from({ length: count }, (_, index) => {
            const slot = session.slots[index];
            const playable = slotPlayable(slot);
            const label = playable ? slot?.title || `Pane ${index + 1}` : "Empty";
            return (
              <button
                key={index}
                type="button"
                className={`audio-cell${index === selected ? " on" : ""}`}
                disabled={busy}
                title={label}
                onClick={() => onSelectPane(index)}
              >
                {label}
              </button>
            );
          })}
        </div>
        <div className="channel-picker-menu">
          <input
            autoFocus
            value={query}
            placeholder="Search channels or shows"
            onChange={(event) => onQuery(event.target.value)}
          />
          <div className="channel-picker-list">
            {filtered.map((channel) => {
              const programme = onNow.get(channel.id);
              const current = selectedSlot?.channel_id === channel.id;
              return (
                <button
                  key={channel.id}
                  type="button"
                  className={`channel-option${current ? " selected" : ""}`}
                  disabled={busy || current}
                  onClick={() => onChoose(channel)}
                >
                  <ProgramArt src={programme?.icon} width={120} height={90} className="channel-art" fallback />
                  <span className="channel-option-copy">
                    <span className="channel-option-name">
                      {channel.number ? `${channel.number} ` : ""}
                      {channel.name}
                    </span>
                    {programme && <span className="channel-option-show">{programme.title}</span>}
                  </span>
                </button>
              );
            })}
            {filtered.length === 0 && <div className="channel-option-empty">No matches</div>}
          </div>
        </div>
        <button
          type="button"
          className="btn btn-ghost change-picker-clear"
          disabled={!canClear || busy}
          onClick={() => onChoose(null)}
        >
          Clear pane
        </button>
        {error && <div className="audio-picker-error">{error}</div>}
      </div>
    </>
  );
}
