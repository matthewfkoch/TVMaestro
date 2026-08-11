import Combine
import Foundation
import UIKit

/// Shared app state: prefs, control server, playback session, and chrome.
@MainActor
final class AppModel: ObservableObject {
    @Published var session: PlaybackSession?
    @Published var statusLine: String = "Starting…"
    @Published var localAddresses: [String] = []
    @Published var port: Int
    @Published var authToken: String
    @Published var lastError: String?
    @Published var streamWarning: String?
    @Published var volumeHUD: String?
    @Published var chromeVisible = true

    private var server: ControlServer?
    private var volumeListener: UUID?
    private var hudHideTask: Task<Void, Never>?
    private var chromeHideTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let port = "controlPort"
        static let token = "authToken"
    }

    var isPlaying: Bool {
        session?.slots.contains(where: \.isPlayable) == true
    }

    var focusTitle: String? {
        session?.slots.first(where: { $0.audio && $0.isPlayable })?.title
            ?? session?.slots.first(where: \.isPlayable)?.title
    }

    init() {
        let storedPort = defaults.object(forKey: Keys.port) as? Int
        port = storedPort ?? 9093
        authToken = defaults.string(forKey: Keys.token) ?? ""
    }

    func start() {
        AudioController.configureAudioSession()
        refreshAddresses()
        restartServer()
        volumeListener = AudioController.shared.addListener { [weak self] in
            Task { @MainActor in
                self?.showVolumeHUD()
            }
        }
    }

    func stop() {
        if let volumeListener {
            AudioController.shared.removeListener(volumeListener)
        }
        volumeListener = nil
        server?.stop()
        server = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func refreshAddresses() {
        localAddresses = LocalIP.ipv4Addresses()
        if !isPlaying {
            statusLine = idleStatus()
        }
    }

    func saveSettings(port: Int, token: String) {
        self.port = max(1024, min(port, 65535))
        authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(self.port, forKey: Keys.port)
        defaults.set(authToken, forKey: Keys.token)
        restartServer()
    }

    func applySession(_ session: PlaybackSession?, warning: String? = nil) {
        self.session = session
        streamWarning = warning
        UIApplication.shared.isIdleTimerDisabled = session?.slots.contains(where: \.isPlayable) == true

        if let session, session.slots.contains(where: \.isPlayable) {
            let playable = session.slots.filter(\.isPlayable).count
            statusLine = "Playing \(playable) · \(session.layout)"
            lastError = nil
            flashChrome()
        } else {
            statusLine = idleStatus()
            chromeVisible = true
        }
    }

    func stopPlayback() {
        server?.clearSessionLocally()
        applySession(nil)
    }

    func reportPlaybackError(_ message: String) {
        lastError = message
        statusLine = message
        flashChrome()
    }

    func testVolumeUp() {
        _ = AudioController.shared.volumeUp()
    }

    func flashChrome() {
        chromeVisible = true
        chromeHideTask?.cancel()
        guard isPlaying else { return }
        chromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                chromeVisible = false
            }
        }
    }

    private func showVolumeHUD() {
        let audio = AudioController.shared
        if audio.isMuted {
            volumeHUD = "Muted"
        } else {
            let pct = Int((audio.gain * 100).rounded())
            volumeHUD = "Volume \(pct)%"
        }
        flashChrome()
        hudHideTask?.cancel()
        hudHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled {
                volumeHUD = nil
            }
        }
    }

    private func restartServer() {
        server?.stop()
        let control = ControlServer(
            port: UInt16(port),
            authToken: authToken,
            audio: AudioController.shared
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .session(let s, let warning):
                    self.applySession(s, warning: warning)
                case .stopped:
                    self.applySession(nil)
                case .failed(let message):
                    self.lastError = message
                    self.statusLine = message
                }
            }
        }
        server = control
        do {
            try control.start()
            if !isPlaying {
                statusLine = idleStatus()
            }
            lastError = nil
        } catch {
            statusLine = "Control API failed: \(error.localizedDescription)"
            lastError = statusLine
        }
    }

    private func idleStatus() -> String {
        let hosts = localAddresses.isEmpty ? ["<no LAN IP>"] : localAddresses
        let list = hosts.map { "\($0):\(port)" }.joined(separator: ", ")
        return "Control API on \(list)"
    }
}
