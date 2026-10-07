import { useEffect, useMemo, useRef, useState } from "react";
import type { Channel, Programme } from "../api";
import ProgramArt from "./ProgramArt";

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
  const rowEls = useRef<Set<HTMLElement>>(new Set());
  const ioRef = useRef<IntersectionObserver | null>(null);
  const [now, setNow] = useState(() => Date.now() / 1000);
  const [hourW, setHourW] = useState(readHourWidth);
  const [artRows, setArtRows] = useState<Set<string>>(() => new Set());

  useEffect(() => {
    const root = wrapRef.current;
    if (!root) return;
    const io = new IntersectionObserver(
      (entries) => {
        setArtRows((prev) => {
          const next = new Set(prev);
          let changed = false;
          for (const entry of entries) {
            if (!entry.isIntersecting) continue;
            const id = (entry.target as HTMLElement).dataset.channelId;
            if (id && !next.has(id)) {
              next.add(id);
              changed = true;
              io.unobserve(entry.target);
            }
          }
          return changed ? next : prev;
        });
      },
      { root, rootMargin: "240px 0px" },
    );
    ioRef.current = io;
    rowEls.current.forEach((el) => io.observe(el));
    return () => {
      io.disconnect();
      ioRef.current = null;
    };
  }, [channels.length]);

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
    // Recenter when the window or hour width changes. Do not depend on `now`:
    // that tick fires every 30s and was pulling the guide back while browsing.
    const current = Date.now() / 1000;
    const offset = ((current - rangeStart) / 3600) * hourW - el.clientWidth * 0.3;
    el.scrollLeft = Math.max(0, offset);
  }, [rangeStart, hourW]);

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
              <div
                className="epg-row"
                key={ch.id}
                data-channel-id={ch.id}
                ref={(el) => {
                  if (!el) return;
                  rowEls.current.add(el);
                  ioRef.current?.observe(el);
                }}
              >
                <button
                  type="button"
                  className="epg-channel"
                  onClick={() => {
                    const live = progs.find((p) => p.start <= now && now < p.stop);
                    if (live) onSelectProgramme(ch, live);
                    else onSelectChannel(ch);
                  }}
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
                    const showArt = artRows.has(ch.id) && Boolean(p.icon) && w >= 120;
                    return (
                      <button
                        type="button"
                        className={`programme${live ? " live" : ""}`}
                        key={`${p.channel_id}-${p.start}-${p.title}`}
                        style={{ left: left + 2, width: w }}
                        onClick={() => onSelectProgramme(ch, p)}
                        title={p.description || p.title}
                      >
                        {showArt && (
                          <ProgramArt src={p.icon} width={160} height={120} className="programme-art" />
                        )}
                        <span className="programme-copy">
                          <div className="programme-title">{p.title}</div>
                          <div className="programme-sub">
                            {p.subtitle ||
                              `${new Date(p.start * 1000).toLocaleTimeString([], {
                                hour: "numeric",
                                minute: "2-digit",
                              })}`}
                          </div>
                        </span>
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
