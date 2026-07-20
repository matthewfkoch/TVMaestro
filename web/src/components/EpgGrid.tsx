import { useEffect, useMemo, useRef, useState } from "react";
import type { Channel, Programme } from "../api";

type Props = {
  channels: Channel[];
  programmes: Programme[];
  rangeStart: number;
  rangeEnd: number;
  onSelectProgramme: (channel: Channel, programme: Programme) => void;
  onSelectChannel: (channel: Channel) => void;
};

function readHourWidth(): number {
  if (typeof window === "undefined") return 280;
  const raw = getComputedStyle(document.documentElement).getPropertyValue("--hour-w");
  const n = parseFloat(raw);
  return Number.isFinite(n) && n > 0 ? n : 280;
}

export default function EpgGrid({
  channels,
  programmes,
  rangeStart,
  rangeEnd,
  onSelectProgramme,
  onSelectChannel,
}: Props) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [now, setNow] = useState(() => Date.now() / 1000);
  const [hourW, setHourW] = useState(readHourWidth);

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now() / 1000), 30_000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    const sync = () => setHourW(readHourWidth());
    sync();
    window.addEventListener("resize", sync);
    return () => window.removeEventListener("resize", sync);
  }, []);

  const pxFor = (ts: number) => ((ts - rangeStart) / 3600) * hourW;

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const offset = pxFor(now) - el.clientWidth * 0.3;
    el.scrollLeft = Math.max(0, offset);
  }, [rangeStart, now, hourW]);

  const hours = useMemo(() => {
    const list: number[] = [];
    for (let t = rangeStart; t < rangeEnd; t += 3600) list.push(t);
    return list;
  }, [rangeStart, rangeEnd]);

  const byChannel = useMemo(() => {
    const map = new Map<string, Programme[]>();
    for (const p of programmes) {
      const arr = map.get(p.channel_id) || [];
      arr.push(p);
      map.set(p.channel_id, arr);
    }
    return map;
  }, [programmes]);

  const width = ((rangeEnd - rangeStart) / 3600) * hourW;
  const nowLeft = pxFor(now);

  if (!channels.length) {
    return (
      <div className="empty-state">
        No channels yet. Check Settings → DVR URLs and refresh guide data.
      </div>
    );
  }

  return (
    <div className="epg-wrap" ref={wrapRef}>
      <div className="epg">
        <div className="epg-times">
          <div className="epg-times-spacer" />
          <div className="epg-time-row" style={{ width }}>
            {hours.map((h) => (
              <div className="epg-time-cell" key={h}>
                {new Date(h * 1000).toLocaleTimeString([], {
                  hour: "numeric",
                  minute: "2-digit",
                })}
              </div>
            ))}
          </div>
        </div>
        <div className="epg-body">
          {now >= rangeStart && now <= rangeEnd && (
            <div
              className="now-line"
              style={{ left: `calc(var(--channel-w) + ${nowLeft}px)` }}
            />
          )}
          {channels.map((ch) => {
            const progs = byChannel.get(ch.id) || [];
            return (
              <div className="epg-row" key={ch.id}>
                <button
                  type="button"
                  className="epg-channel"
                  onClick={() => onSelectChannel(ch)}
                  title={`Tune ${ch.name}`}
                >
                  {ch.logo ? <img src={ch.logo} alt="" /> : <div style={{ width: 36 }} />}
                  <div className="epg-channel-meta">
                    <div className="epg-channel-num">{ch.number || "—"}</div>
                    <div className="epg-channel-name">{ch.name}</div>
                  </div>
                </button>
                <div className="epg-track" style={{ width }}>
                  {progs.map((p) => {
                    const left = pxFor(Math.max(p.start, rangeStart));
                    const right = pxFor(Math.min(p.stop, rangeEnd));
                    const w = Math.max(right - left - 4, 24);
                    const live = p.start <= now && p.stop > now;
                    return (
                      <button
                        type="button"
                        className={`programme${live ? " live" : ""}`}
                        key={`${p.channel_id}-${p.start}-${p.title}`}
                        style={{ left: left + 2, width: w }}
                        onClick={() => onSelectProgramme(ch, p)}
                        title={p.description || p.title}
                      >
                        <div className="programme-title">{p.title}</div>
                        <div className="programme-sub">
                          {p.subtitle ||
                            `${new Date(p.start * 1000).toLocaleTimeString([], {
                              hour: "numeric",
                              minute: "2-digit",
                            })}`}
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
