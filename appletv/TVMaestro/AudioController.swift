import AVFoundation
import Foundation

/// App-level gain / mute applied to the audio-focus pane.
/// tvOS cannot inject HDMI-CEC volume keys; this mirrors Android's usable volume path inside the player.
final class AudioController: @unchecked Sendable {
    static let shared = AudioController()

    private let lock = NSLock()
    private var gainValue: Float = 1.0
    private var mutedValue = false
    private var listeners: [UUID: () -> Void] = [:]

    var gain: Float {
        lock.lock(); defer { lock.unlock() }
        return gainValue
    }

    var isMuted: Bool {
        lock.lock(); defer { lock.unlock() }
        return mutedValue
    }

    @discardableResult
    func volumeUp() -> Bool {
        lock.lock()
        mutedValue = false
        gainValue = min(1.0, gainValue + 0.1)
        lock.unlock()
        notify()
        return true
    }

    @discardableResult
    func volumeDown() -> Bool {
        lock.lock()
        gainValue = max(0.0, gainValue - 0.1)
        if gainValue <= 0.001 {
            mutedValue = true
            gainValue = 0
        }
        lock.unlock()
        notify()
        return true
    }

    @discardableResult
    func toggleMute() -> Bool {
        lock.lock()
        mutedValue.toggle()
        if !mutedValue && gainValue <= 0.001 {
            gainValue = 0.5
        }
        lock.unlock()
        notify()
        return true
    }

    func effectiveVolume(slotHasAudioFocus: Bool) -> Float {
        lock.lock()
        let g = gainValue
        let m = mutedValue
        lock.unlock()
        guard slotHasAudioFocus else { return 0 }
        return m ? 0 : g
    }

    func capabilities() -> [String: Any] {
        [
            "power": false,
            "volume": true,
            "mute": true,
            "method": "player_gain",
            "power_detail": "tvOS cannot wake/sleep the TV from this app. Use the Siri Remote or Apple TV HDMI-CEC system settings. Volume/mute adjust in-app gain on the audio-focus stream.",
            "gain": gain,
            "muted": isMuted,
        ]
    }

    func addListener(_ block: @escaping () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        listeners[id] = block
        lock.unlock()
        return id
    }

    func removeListener(_ id: UUID) {
        lock.lock()
        listeners[id] = nil
        lock.unlock()
    }

    private func notify() {
        lock.lock()
        let blocks = Array(listeners.values)
        lock.unlock()
        DispatchQueue.main.async {
            blocks.forEach { $0() }
        }
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
