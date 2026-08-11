import Foundation

enum StreamURL {
    /// Channels DVR and similar often serve MPEG-TS with `format=ts` — AVPlayer is unreliable for those.
    static func looksLikeMpegTS(_ raw: String) -> Bool {
        let url = raw.lowercased()
        if url.contains(".m3u8") { return false }
        if url.contains("format=hls") { return false }
        if url.contains("format=ts") || url.contains("format=mpegts") {
            return true
        }
        // Bare transport-stream path (not an HLS playlist).
        if let path = URL(string: raw)?.path.lowercased(), path.hasSuffix(".ts") {
            return true
        }
        return false
    }

    /// Best-effort rewrite toward HLS when Channels DVR query params are present.
    static func preferHLS(_ raw: String) -> String {
        guard looksLikeMpegTS(raw), var components = URLComponents(string: raw) else { return raw }
        var items = components.queryItems ?? []
        var changed = false
        if let idx = items.firstIndex(where: { $0.name.lowercased() == "format" }) {
            if items[idx].value?.lowercased() != "hls" {
                items[idx].value = "hls"
                changed = true
            }
        }
        if changed {
            components.queryItems = items
            return components.string ?? raw
        }
        return raw
    }
}
