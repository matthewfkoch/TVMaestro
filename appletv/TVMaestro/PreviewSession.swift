import Foundation

/// Bundled sample grid so review can play the player without a home server.
enum PreviewSession {
    static let credit = "Sample: Big Buck Bunny, Blender Foundation"

    private static let clips: [(name: String, title: String)] = [
        ("preview-nature", "Nature"),
        ("preview-afternoon", "Afternoon"),
        ("preview-movie", "Movie"),
        ("preview-kids", "Kids"),
    ]

    static func make() -> PlaybackSession? {
        var slots: [SessionSlot] = []
        for (index, clip) in clips.enumerated() {
            guard let url = Bundle.main.url(forResource: clip.name, withExtension: "mp4") else {
                return nil
            }
            slots.append(
                SessionSlot(
                    channel_id: "preview-\(index)",
                    url: url.absoluteString,
                    title: clip.title,
                    audio: index == 0
                )
            )
        }
        return PlaybackSession(id: "preview", mode: "multiview", layout: "2x2", slots: slots)
    }
}
