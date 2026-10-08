import Foundation

struct SessionSlot: Codable, Equatable, Identifiable {
    var id: String { "\(channel_id ?? "")|\(url ?? "")|\(title ?? "")" }
    var channel_id: String?
    var url: String?
    var title: String?
    var audio: Bool

    enum CodingKeys: String, CodingKey {
        case channel_id, url, title, audio
    }

    init(channel_id: String? = nil, url: String? = nil, title: String? = nil, audio: Bool = false) {
        self.channel_id = channel_id
        self.url = url
        self.title = title
        self.audio = audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel_id = try c.decodeIfPresent(String.self, forKey: .channel_id)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? false
    }

    var isPlayable: Bool {
        guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }
}

struct PlaybackSession: Codable, Equatable {
    var id: String?
    var mode: String
    var layout: String
    var slots: [SessionSlot]

    enum CodingKeys: String, CodingKey {
        case id, mode, layout, slots
    }

    init(id: String? = nil, mode: String = "single", layout: String = "1", slots: [SessionSlot]) {
        self.id = id
        self.mode = mode
        self.layout = layout
        self.slots = slots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "single"
        layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? "1"
        slots = try c.decodeIfPresent([SessionSlot].self, forKey: .slots) ?? []
    }
}

enum LayoutGeometry {
    static func dims(_ layout: String) -> (rows: Int, cols: Int) {
        switch layout {
        case "2x1": return (1, 2)
        case "1x2": return (2, 1)
        case "2x2": return (2, 2)
        case "3x3": return (3, 3)
        default: return (1, 1)
        }
    }

    static func capacity(_ layout: String) -> Int {
        let d = dims(layout)
        return d.rows * d.cols
    }
}
