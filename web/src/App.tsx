import { useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  type Channel,
  type Device,
  type Programme,
  type Session,
  type Status,
} from "./api";
import AddDeviceModal from "./components/AddDeviceModal";
import DeviceBar from "./components/DeviceBar";
import EditDeviceModal from "./components/EditDeviceModal";
import EpgGrid from "./components/EpgGrid";
import Logo from "./components/Logo";
import MultiviewComposer, {
  CAPACITY,
  type LayoutId,
} from "./components/MultiviewComposer";
import SettingsModal from "./components/SettingsModal";
import TuneSheet from "./components/TuneSheet";
import YoutubeModal from "./components/YoutubeModal";

type TuneTarget = { channel: Channel; programme?: Programme | null };

export default function App() {
  const [status, setStatus] = useState<Status | null>(null);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [programmes, setProgrammes] = useState<Programme[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | null>(null);
  const [tune, setTune] = useState<TuneTarget | null>(null);
  const [multiviewOpen, setMultiviewOpen] = useState(false);
  const [mvLayout, setMvLayout] = useState<LayoutId>("2x2");
  const [mvSlots, setMvSlots] = useState<Array<Channel | null>>([null, null, null, null]);
  const [audioIndex, setAudioIndex] = useState(0);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [addDeviceOpen, setAddDeviceOpen] = useState(false);
  const [editDeviceId, setEditDeviceId] = useState<string | null>(null);
  const [youtubeOpen, setYoutubeOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [clock, setClock] = useState(() => Date.now());

  useEffect(() => {
    const id = window.setInterval(() => setClock(Date.now()), 60_000);
    return () => clearInterval(id);
  }, []);

  const range = useMemo(() => {
    const now = Math.floor(clock / 1000);
    const start = now - (now % 3600) - 3600;
    const end = start + 12 * 3600;
    return { start, end };
  }, [clock, status?.epg_updated_at]);

  const reload = useCallback(async () => {
    try {
      const [st, ch, epg, dev, sess] = await Promise.all([
        api.status(),
        api.channels(),
        api.epg(range.start, range.end),
        api.devices(),
        api.sessions(),
      ]);
      setStatus(st);
      setChannels(ch);
      setProgrammes(epg);
      setDevices(dev);
      setSessions(sess);
      setLoadError(null);
      setSelectedDeviceId((prev) => {
        if (prev && dev.some((d) => d.id === prev)) return prev;
        return dev[0]?.id ?? null;
      });
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : String(e));
    }
  }, [range.start, range.end]);

  useEffect(() => {
    void reload();
    const id = window.setInterval(() => void reload(), 15_000);
    return () => clearInterval(id);
  }, [reload]);

  const sessionsByDevice = useMemo(() => {
    const rank = (status: string) =>
      status === "playing" || status === "pending" ? 2 : status === "error" ? 0 : 1;
    const map: Record<string, Session | undefined> = {};
    for (const s of sessions) {
      if (s.status === "stopped") continue;
      const existing = map[s.device_id];
      if (!existing || rank(s.status) >= rank(existing.status)) {
        map[s.device_id] = s;
      }
    }
    return map;
  }, [sessions]);

  const selectedDevice = devices.find((d) => d.id === selectedDeviceId) || null;
  const selectedSupportsMultiview = (selectedDevice?.capabilities?.multiview_max ?? 1) > 1;
  const editDevice = devices.find((d) => d.id === editDeviceId) || null;

  function openTune(channel: Channel, programme?: Programme | null) {
    setError(null);
    setTune({ channel, programme });
  }

  async function playSingle() {
    if (!tune || !selectedDeviceId) return;
    setBusy(true);
    setError(null);
    try {
      await api.createSession({
        device_id: selectedDeviceId,
        mode: "single",
        layout: "1",
        slots: [
          {
            channel_id: tune.channel.id,
            title: tune.programme?.title || tune.channel.name,
            audio: true,
          },
        ],
      });
      setTune(null);
      await reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function sendMultiview() {
    if (!selectedDeviceId) return;
    setBusy(true);
    setError(null);
    try {
      const max = Math.max(1, selectedDevice?.capabilities?.multiview_max ?? 1);
      if (max <= 1) {
        throw new Error(
          selectedDevice?.capabilities?.chip_note ||
            "This device does not support multiview",
        );
      }
      let layout = mvLayout;
      if (CAPACITY[layout] > max) {
        layout = max >= 2 ? "2x1" : "1";
      }
      const cap = Math.min(CAPACITY[layout], max);
      // Keep empty middle slots so Android grid positions match the composer.
      const slots = mvSlots.slice(0, cap).map((ch, i) =>
        ch
          ? {
              channel_id: ch.id,
              title: ch.name,
              audio: i === audioIndex,
            }
          : { audio: false },
      );
      if (!slots.some((s) => "channel_id" in s && s.channel_id)) {
        throw new Error("Add at least one channel");
      }
      const filled = slots.filter((s) => "channel_id" in s && s.channel_id);
      if (!slots.some((s) => s.audio && "channel_id" in s && s.channel_id)) {
        filled[0].audio = true;
      }
      await api.createSession({
        device_id: selectedDeviceId,
        mode: filled.length > 1 ? "multiview" : "single",
        layout,
        slots,
      });
      setMultiviewOpen(false);
      await reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <Logo className="brand-mark" />
        </div>
        <div className="topbar-actions">
          {status && (
            <span className={`pill${status.last_error ? " warn" : ""}`}>
              {status.channels} ch · {status.programmes.toLocaleString()} airings
              {status.last_error ? " · sync error" : ""}
            </span>
          )}
          <button
            type="button"
            className="btn"
            disabled={!selectedSupportsMultiview}
            title={
              selectedSupportsMultiview
                ? "Multiview"
                : selectedDevice?.capabilities?.chip_note ||
                  "Selected device does not support multiview"
            }
            onClick={() => {
              setMvSlots([null, null, null, null]);
              setMultiviewOpen(true);
            }}
          >
            Multiview
          </button>
          <button
            type="button"
            className="btn"
            onClick={() => void api.refresh().then(reload).catch((e: Error) => setLoadError(e.message))}
          >
            Refresh
          </button>
          <button type="button" className="btn" onClick={() => setSettingsOpen(true)}>
            Settings
          </button>
        </div>
      </header>

      <main className="main">
        {loadError && (
          <div className="empty-state error">
            Failed to load: {loadError}
          </div>
        )}
        {!loadError && (
          <EpgGrid
            channels={channels}
            programmes={programmes}
            rangeStart={range.start}
            rangeEnd={range.end}
            onSelectChannel={(ch) => openTune(ch)}
            onSelectProgramme={(ch, p) => openTune(ch, p)}
          />
        )}

        {tune && (
          <TuneSheet
            channel={tune.channel}
            programme={tune.programme}
            devices={devices}
            selectedDeviceId={selectedDeviceId}
            onSelectDevice={setSelectedDeviceId}
            onPlay={() => void playSingle()}
            onMultiview={() => {
              const next = [...mvSlots];
              next[0] = tune.channel;
              setMvSlots(next);
              setTune(null);
              setMultiviewOpen(true);
            }}
            onYoutube={() => {
              setTune(null);
              setYoutubeOpen(true);
            }}
            onClose={() => setTune(null)}
            busy={busy}
            error={error}
          />
        )}

        {multiviewOpen && (
          <MultiviewComposer
            channels={channels}
            programmes={programmes}
            devices={devices}
            deviceId={selectedDeviceId}
            layout={mvLayout}
            slots={mvSlots}
            audioIndex={audioIndex}
            onLayout={setMvLayout}
            onDevice={setSelectedDeviceId}
            onSetSlot={(i, ch) => {
              const next = [...mvSlots];
              next[i] = ch;
              setMvSlots(next);
            }}
            onAudio={setAudioIndex}
            onSend={() => void sendMultiview()}
            onClose={() => setMultiviewOpen(false)}
            busy={busy}
            error={error}
          />
        )}
      </main>

      <DeviceBar
        devices={devices}
        selectedId={selectedDeviceId}
        sessionsByDevice={sessionsByDevice}
        onSelect={setSelectedDeviceId}
        onEdit={setEditDeviceId}
        onCec={(id, action) => void api.cec(id, action).catch((e: Error) => setLoadError(e.message))}
        onStop={(id) =>
          void api
            .stopSession(id)
            .then(reload)
            .catch((e: Error) => setLoadError(e.message))
        }
        onAdd={() => setAddDeviceOpen(true)}
      />

      <SettingsModal
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onSaved={() => void reload()}
      />
      <AddDeviceModal
        open={addDeviceOpen}
        onClose={() => setAddDeviceOpen(false)}
        onAdded={() => void reload()}
      />
      <EditDeviceModal
        open={!!editDeviceId}
        device={editDevice}
        onClose={() => setEditDeviceId(null)}
        onSaved={() => void reload()}
      />
      <YoutubeModal
        open={youtubeOpen}
        devices={devices}
        deviceId={selectedDeviceId}
        onClose={() => setYoutubeOpen(false)}
        onPlayed={() => void reload()}
      />
    </div>
  );
}
