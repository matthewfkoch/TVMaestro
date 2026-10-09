import Combine
import Foundation
import KSPlayer
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
    @Published var guideSeen = false
    @Published var guidePaired = false
    @Published var isPreview = false

    private var server: ControlServer?
    private var volumeListener: UUID?
    private var hudHideTask: Task<Void, Never>?
    private var chromeHideTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let port = "controlPort"
        static let token = "authToken"
        static let guideSeen = "guideSeen"
        static let guidePaired = "guidePaired"
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
        guideSeen = defaults.bool(forKey: Keys.guideSeen)
        guidePaired = defaults.bool(forKey: Keys.guidePaired)
    }

    var idleDetail: String {
        if guideSeen && guidePaired {
            return "Paired with the guide. Waiting for a session."
        }
        if guideSeen {
            return "Added to the guide. Pair it under Edit device so the guide can open this app."
        }
        return "Add this address in the web guide, then pair under Edit device."
    }

    func noteGuideLink(registered: Bool, paired: Bool) {
        guideSeen = registered
        guidePaired = paired
        defaults.set(registered, forKey: Keys.guideSeen)
        defaults.set(paired, forKey: Keys.guidePaired)
    }

    func start() {
        KSOptions.firstPlayerType = KSMEPlayer.self
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

    /// tvOS drops the listening socket while the app is suspended. Rebind when it returns
    /// to the foreground so a remote Open / tune can reach the control API again.
    func resumeFromForeground() {
        refreshAddresses()
        guard let server else {
            restartServer()
            return
        }
        if server.isListening {
            if !isPlaying {
                statusLine = idleStatus()
            }
            return
        }
        do {
            try server.restartListening()
            if !isPlaying {
                statusLine = idleStatus()
            }
            lastError = nil
        } catch {
            statusLine = "Control API failed: \(error.localizedDescription)"
            lastError = statusLine
        }
    }

    func saveSettings(port: Int, token: String) {
        self.port = max(1024, min(port, 65535))
        authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(self.port, forKey: Keys.port)
        defaults.set(authToken, forKey: Keys.token)
        restartServer()
    }

    func startPreview() {
        guard let session = PreviewSession.make() else {
            lastError = "Sample clips are missing."
            statusLine = lastError ?? "Sample clips are missing."
            return
        }
        applySession(session, preview: true)
    }

    func applySession(_ session: PlaybackSession?, warning: String? = nil, preview: Bool = false) {
        isPreview = preview && session?.slots.contains(where: \.isPlayable) == true
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
                case .guide(let registered, let paired):
                    self.noteGuideLink(registered: registered, paired: paired)
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
        idleDetail
    }
}
