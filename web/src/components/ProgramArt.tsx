import { useEffect, useState } from "react";

/** Resize Channels/TMS artwork. Keeps the source aspect ratio so the CDN does not crop it. */
export function artUrl(src: string | null | undefined, width: number, height: number): string | null {
  if (!src || !/^https?:\/\//i.test(src)) return null;
  try {
    const url = new URL(src);
    if (url.searchParams.has("w") || url.hostname.endsWith("fancybits.co")) {
      const srcW = Number(url.searchParams.get("w"));
      const srcH = Number(url.searchParams.get("h"));
      const targetH =
        srcW > 0 && srcH > 0 ? Math.max(1, Math.round(width * (srcH / srcW))) : height;
      url.searchParams.set("w", String(width));
      url.searchParams.set("h", String(targetH));
    }
    return url.toString();
  } catch {
    return src;
  }
}

type Props = {
  src?: string | null;
  width: number;
  height: number;
  className?: string;
  fallback?: boolean;
};

export default function ProgramArt({ src, width, height, className, fallback = false }: Props) {
  const sized = artUrl(src, width, height);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    setFailed(false);
  }, [sized]);

  if (!sized || failed) {
    if (!fallback) return null;
    return <span className={`program-art-fallback ${className || ""}`} aria-hidden="true" />;
  }

  return (
    <img
      className={className ? `program-art ${className}` : "program-art"}
      src={sized}
      alt=""
      loading="lazy"
      decoding="async"
      onError={() => setFailed(true)}
    />
  );
}
