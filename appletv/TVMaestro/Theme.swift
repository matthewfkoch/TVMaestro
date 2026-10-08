import SwiftUI

enum Theme {
    static let bg = Color(red: 14.0 / 255, green: 18.0 / 255, blue: 24.0 / 255)
    static let panelSolid = Color(red: 21.0 / 255, green: 27.0 / 255, blue: 36.0 / 255)
    static let accent = Color(red: 62.0 / 255, green: 207.0 / 255, blue: 142.0 / 255)
    static let text = Color(red: 232.0 / 255, green: 238.0 / 255, blue: 246.0 / 255)
    static let dim = Color(red: 139.0 / 255, green: 155.0 / 255, blue: 176.0 / 255)
    static let faint = Color(red: 93.0 / 255, green: 109.0 / 255, blue: 130.0 / 255)
    static let warn = Color(red: 240.0 / 255, green: 179.0 / 255, blue: 90.0 / 255)
    static let danger = Color(red: 239.0 / 255, green: 107.0 / 255, blue: 107.0 / 255)
    static let muted = dim
    static let panel = panelSolid
    static let panelStroke = Color.white.opacity(0.16)
}
