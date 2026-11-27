import AVFoundation
import Foundation

/// Playback stays at full scale. Guide volume and mute are the Siri Remote's
/// volume, sent by the paired guide over Companion — not a second in-app gain.
final class AudioController: @unchecked Sendable {
    static let shared = AudioController()

    func capabilities() -> [String: Any] {
        [
            "power": false,
            "volume": true,
            "mute": true,
            "method": "appletv_companion",
            "power_detail": "Volume and mute in the guide use the same controls as the Siri Remote. Pair the Apple TV in the guide first. The television follows when Control TVs and Receivers is on.",
        ]
    }

    static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            NSLog("TVMaestro audio session: \(error.localizedDescription)")
        }
    }
}
