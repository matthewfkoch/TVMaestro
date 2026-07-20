import { useState } from "react";
import { api } from "../api";

type Props = {
  open: boolean;
  onClose: () => void;
  onAdded: () => void;
};

export default function AddDeviceModal({ open, onClose, onAdded }: Props) {
  const [name, setName] = useState("Living Room");
  const [host, setHost] = useState("");
  const [port, setPort] = useState(9093);
  const [token, setToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (!open) return null;

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await api.createDevice({ name, host, port, token: token || undefined });
      onAdded();
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
        <h2>Add Android TV device</h2>
        <div style={{ display: "grid", gap: "0.75rem" }}>
          <div className="field">
            <label>Name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="field">
            <label>Host / IP</label>
            <input
              value={host}
              placeholder="192.168.1.50"
              onChange={(e) => setHost(e.target.value)}
            />
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
            <input value={token} onChange={(e) => setToken(e.target.value)} />
          </div>
        </div>
        {error && <div className="error" style={{ marginTop: "0.75rem" }}>{error}</div>}
        <div className="modal-actions">
          <button type="button" className="btn" onClick={onClose}>
            Cancel
          </button>
          <button
            type="button"
            className="btn btn-primary"
            disabled={!host || !name || busy}
            onClick={submit}
          >
            {busy ? "Adding…" : "Add device"}
          </button>
        </div>
      </div>
    </div>
  );
}
