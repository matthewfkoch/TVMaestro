import { useEffect, useState } from "react";
import { api, REDACTED_SECRET, type Device } from "../api";
import { isAppleTvDevice, isFireOsDevice } from "../streamCompat";

type Props = {
  open: boolean;
  device: Device | null;
  onClose: () => void;
  onSaved: () => void;
};

export default function EditDeviceModal({ open, device, onClose, onSaved }: Props) {
  const [name, setName] = useState("");
  const [host, setHost] = useState("");
  const [port, setPort] = useState(9093);
  const [token, setToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [paired, setPaired] = useState<{ id: string; value: boolean } | null>(null);
  const [pairOpen, setPairOpen] = useState(false);
  const [pin, setPin] = useState("");
  const [pairMsg, setPairMsg] = useState<string | null>(null);
  const [launching, setLaunching] = useState(false);

  useEffect(() => {
    if (!device) return;
    const deviceId = device.id;
    setName(device.name);
    setHost(device.host);
    setPort(device.port);
    setToken(device.token || "");
    setError(null);
    setPairOpen(false);
    setPin("");
    setPairMsg(null);
    setLaunching(false);
    setPaired(null);
    void api
      .pairStatus(deviceId)
      .then((s) => setPaired({ id: deviceId, value: s.paired }))
      .catch(() => setPaired({ id: deviceId, value: false }));
    // Reload replaces the device object every poll. Key off id so an open PIN
    // field or “app opened” note is not wiped while this modal stays on the same device.
  }, [device?.id]);

  if (!open || !device) return null;

  async function save() {
    setBusy(true);
    setError(null);
    try {
      const body: { name: string; host: string; port: number; token?: string } = {
        name,
        host,
        port,
      };
      // Omit unchanged redacted token so the server keeps the real value.
      if (token !== REDACTED_SECRET) body.token = token;
      await api.updateDevice(device!.id, body);
      onSaved();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!confirm(`Remove device “${device!.name}”?`)) return;
    setBusy(true);
    setError(null);
    try {
      await api.deleteDevice(device!.id);
      onSaved();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function openApp() {
    setLaunching(true);
    setError(null);
    setPairMsg(null);
    try {
      await api.launch(device!.id);
      setPairMsg("TVMaestro is open on this Apple TV.");
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLaunching(false);
    }
  }

  async function startPair() {
    setBusy(true);
    setError(null);
    setPairMsg(null);
    try {
      const r = await api.pairStart(device!.id);
      setPairOpen(true);
      setPairMsg(r.message || "Enter the PIN shown on the TV, then complete pairing.");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function finishPair() {
    setBusy(true);
    setError(null);
    try {
      await api.pairFinish(device!.id, pin.trim());
      setPaired({ id: device!.id, value: true });
      setPairOpen(false);
      setPin("");
      setPairMsg(
        isAppleTvDevice(device!)
          ? "Paired — the guide can open TVMaestro on this Apple TV."
          : "Paired — Wake/Sleep will use Android TV Remote (no ADB).",
      );
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const caps = device.capabilities;
  const appleTv = isAppleTvDevice(device);
  const fireOs = isFireOsDevice(device);
  const pairedNow = paired?.id === device.id ? paired.value : null;
  const showPairHelp = pairedNow === false;

  return (
    <div className="modal-center">
      <div className="modal">
        <h2>Edit device</h2>
        <p style={{ color: "var(--text-dim)", marginTop: 0, fontSize: "0.85rem" }}>
          {device.model || "Unknown model"}
          {caps?.chip_family ? ` · ${caps.chip_family}` : ""}
          {caps?.multiview_max != null ? ` · multiview max ${caps.multiview_max}` : ""}
          {caps?.chip_note ? ` — ${caps.chip_note}` : ""}
        </p>
        <div style={{ display: "grid", gap: "0.75rem" }}>
          <div className="field">
            <label>Name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="field">
            <label>Host / IP</label>
            <input value={host} onChange={(e) => setHost(e.target.value)} />
          </div>
          <div className="field">
            <label>Control port</label>
            <input
              type="number"
              value={port}
              onChange={(e) => setPort(Number(e.target.value) || 9093)}
            />
          </div>
          <div className="field">
            <label>Auth token (optional)</label>
            <input
              type="password"
              autoComplete="off"
              value={token}
              placeholder={
                token === REDACTED_SECRET
                  ? "Stored — leave unchanged or enter a new token"
                  : undefined
              }
              onChange={(e) => setToken(e.target.value)}
            />
          </div>
          {!appleTv && !fireOs && (
          <div
            style={{
              borderTop: "1px solid var(--line)",
              paddingTop: "0.75rem",
              display: "grid",
              gap: "0.5rem",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "0.75rem", flexWrap: "wrap" }}>
              <strong style={{ fontSize: "0.9rem" }}>Android TV Remote</strong>
              <span
                className={`pill ${pairedNow ? "" : "warn"}`}
                title="Wake/Sleep without ADB after pairing"
              >
                {pairedNow == null ? "…" : pairedNow ? "Paired" : "Not paired"}
              </span>
              <button type="button" className="btn" disabled={busy} onClick={() => void startPair()}>
                {pairedNow ? "Re-pair" : "Pair"}
              </button>
            </div>
            {showPairHelp && (
            <p style={{ margin: 0, color: "var(--text-dim)", fontSize: "0.8rem" }}>
              Pair once (PIN on TV) for Wake/Sleep without ADB. Google TV / Shield / Android TV only —
              not Fire OS. ADB remains a fallback if unpaired.
            </p>
            )}
            {pairOpen && (
              <div className="field">
                <label>PIN from TV</label>
                <input
                  value={pin}
                  onChange={(e) => setPin(e.target.value)}
                  placeholder="e.g. A1B2"
                  autoFocus
                />
                <button
                  type="button"
                  className="btn btn-primary"
                  style={{ marginTop: "0.5rem" }}
                  disabled={!pin.trim() || busy}
                  onClick={() => void finishPair()}
                >
                  Complete pairing
                </button>
              </div>
            )}
            {pairMsg && (
              <p style={{ margin: 0, color: "var(--accent)", fontSize: "0.85rem" }}>{pairMsg}</p>
            )}
          </div>
          )}
          {appleTv && (
          <div
            style={{
              borderTop: "1px solid var(--line)",
              paddingTop: "0.75rem",
              display: "grid",
              gap: "0.5rem",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "0.75rem", flexWrap: "wrap" }}>
              <strong style={{ fontSize: "0.9rem" }}>Open from the guide</strong>
              <span className={`pill ${pairedNow ? "" : "warn"}`} title="Required before the guide can launch the app">
                {pairedNow == null ? "…" : pairedNow ? "Paired" : "Not paired"}
              </span>
              <button type="button" className="btn" disabled={busy || launching} onClick={() => void startPair()}>
                {pairedNow ? "Re-pair" : "Pair"}
              </button>
              <button type="button" className="btn" disabled={busy || launching} onClick={() => void openApp()}>
                {launching ? "Opening…" : "Open app"}
              </button>
            </div>
            {showPairHelp && (
            <p style={{ margin: 0, color: "var(--text-dim)", fontSize: "0.8rem" }}>
              Pair once (PIN on the Apple TV) so Tune and Open can launch TVMaestro when it is not in
              front. The Apple TV has to be awake. This does not turn the television on.
            </p>
            )}
            {pairedNow === true && (
            <p style={{ margin: 0, color: "var(--text-dim)", fontSize: "0.8rem" }}>
              The Apple TV has to be awake. This does not turn the television on.
            </p>
            )}
            {pairOpen && (
              <div className="field">
                <label>PIN from Apple TV</label>
                <input
                  value={pin}
                  onChange={(e) => setPin(e.target.value)}
                  placeholder="e.g. 1234"
                  autoFocus
                />
                <button
                  type="button"
                  className="btn btn-primary"
                  style={{ marginTop: "0.5rem" }}
                  disabled={!pin.trim() || busy}
                  onClick={() => void finishPair()}
                >
                  Complete pairing
                </button>
              </div>
            )}
            {pairMsg && (
              <p style={{ margin: 0, color: "var(--accent)", fontSize: "0.85rem" }}>{pairMsg}</p>
            )}
          </div>
          )}
        </div>
        {error && (
          <div className="error" style={{ marginTop: "0.75rem" }}>
            {error}
          </div>
        )}
        <div className="modal-actions" style={{ justifyContent: "space-between" }}>
          <button type="button" className="btn btn-danger" disabled={busy} onClick={() => void remove()}>
            Remove
          </button>
          <div style={{ display: "flex", gap: "0.5rem" }}>
            <button type="button" className="btn" onClick={onClose}>
              Cancel
            </button>
            <button
              type="button"
              className="btn btn-primary"
              disabled={!host || !name || busy}
              onClick={() => void save()}
            >
              {busy ? "Saving…" : "Save"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
