import { useState } from "react";
import type { Device, Session } from "../api";
import { isAppleTvDevice } from "../streamCompat";

type Props = {
  devices: Device[];
  selectedId: string | null;
  sessionsByDevice: Record<string, Session | undefined>;
  onSelect: (id: string) => void;
  onEdit: (id: string) => void;
  onCec: (id: string, action: string) => void;
  onStop: (sessionId: string) => void;
  onLaunch: (id: string) => Promise<void>;
  onAdd: () => void;
};

export default function DeviceBar({
  devices,
  selectedId,
  sessionsByDevice,
  onSelect,
  onEdit,
  onCec,
  onStop,
  onLaunch,
  onAdd,
}: Props) {
  const [launchingId, setLaunchingId] = useState<string | null>(null);
  const [launchNote, setLaunchNote] = useState<string | null>(null);

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
    </footer>
  );
}
