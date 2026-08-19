import { useEffect, useState } from "react";
import { api, REDACTED_SECRET, type AppConfig } from "../api";

type Props = {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
};

export default function SettingsModal({ open, onClose, onSaved }: Props) {
  const [cfg, setCfg] = useState<AppConfig | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [tunerStatus, setTunerStatus] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    api
      .config()
      .then(setCfg)
      .catch((e: Error) => setError(e.message));
    api
      .apitunerStatus()
      .then((s) => {
        if (!s.enabled) setTunerStatus("APITuner not configured");
        else if (s.error) setTunerStatus(`APITuner error: ${s.error}`);
        else setTunerStatus("APITuner reachable");
      })
      .catch(() => setTunerStatus(null));
  }, [open]);

  if (!open) return null;

  async function save() {
    if (!cfg) return;
    setSaving(true);
    setError(null);
    try {
      await api.saveConfig(cfg);
      await api.refresh();
      onSaved();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-center">
      <div className="modal">
        <h2>Settings</h2>
        {!cfg && !error && <p>Loading…</p>}
        {cfg && (
          <div style={{ display: "grid", gap: "0.75rem" }}>
            <div className="field">
              <label>Channels DVR M3U URL</label>
              <input
                value={cfg.channels_dvr_m3u_url}
                onChange={(e) => setCfg({ ...cfg, channels_dvr_m3u_url: e.target.value })}
              />
            </div>
            <div className="field">
              <label>Channels DVR XMLTV URL</label>
              <input
                value={cfg.channels_dvr_xmltv_url}
                onChange={(e) => setCfg({ ...cfg, channels_dvr_xmltv_url: e.target.value })}
              />
            </div>
            <div className="field">
              <label>APITuner base URL (YouTube)</label>
              <input
                value={cfg.apituner_base_url}
                placeholder="http://192.168.1.x:6592"
                onChange={(e) => setCfg({ ...cfg, apituner_base_url: e.target.value })}
              />
            </div>
            <div className="field">
              <label>APITuner auth token</label>
              <input
                type="password"
                autoComplete="off"
                value={cfg.apituner_auth_token}
                placeholder={
                  cfg.apituner_auth_token === REDACTED_SECRET
                    ? "Stored — leave unchanged or enter a new token"
                    : "Optional"
                }
                onChange={(e) => setCfg({ ...cfg, apituner_auth_token: e.target.value })}
              />
            </div>
            {tunerStatus && (
              <p style={{ margin: 0, color: "var(--text-dim)", fontSize: "0.85rem" }}>{tunerStatus}</p>
            )}
            <div className="field">
              <label>M3U refresh (seconds)</label>
              <input
                type="number"
                value={cfg.m3u_refresh_seconds}
                onChange={(e) =>
                  setCfg({ ...cfg, m3u_refresh_seconds: Number(e.target.value) || 300 })
                }
              />
            </div>
            <div className="field">
              <label>XMLTV refresh (seconds)</label>
              <input
                type="number"
                value={cfg.xmltv_refresh_seconds}
                onChange={(e) =>
                  setCfg({ ...cfg, xmltv_refresh_seconds: Number(e.target.value) || 900 })
                }
              />
            </div>
          </div>
        )}
        {error && <div className="error" style={{ marginTop: "0.75rem" }}>{error}</div>}
        <div className="modal-actions">
          <button type="button" className="btn" onClick={onClose}>
            Cancel
          </button>
          <button type="button" className="btn btn-primary" disabled={!cfg || saving} onClick={save}>
            {saving ? "Saving…" : "Save & refresh"}
          </button>
        </div>
      </div>
    </div>
  );
}
