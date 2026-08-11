import Combine
import Foundation
import UIKit

/// Shared app state: prefs, control server, and the active playback session.
@MainActor
final class AppModel: ObservableObject {
    @Published var session: PlaybackSession?
    @Published var statusLine: String = "Starting…"
    @Published var localAddresses: [String] = []
    @Published var port: Int
    @Published var authToken: String
    @Published var lastError: String?

    private var server: ControlServer?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let port = "controlPort"
        static let token = "authToken"
    }

    init() {
        let storedPort = defaults.object(forKey: Keys.port) as? Int
        port = storedPort ?? 9093
        authToken = defaults.string(forKey: Keys.token) ?? ""
    }

    func start() {
        localAddresses = LocalIP.ipv4Addresses()
        restartServer()
    }

    func stop() {
        server?.stop()
        server = nil
    }

    func saveSettings(port: Int, token: String) {
        self.port = max(1024, min(port, 65535))
        authToken = token
        defaults.set(self.port, forKey: Keys.port)
        defaults.set(authToken, forKey: Keys.token)
        restartServer()
    }

    func applySession(_ session: PlaybackSession?) {
        self.session = session
        if let session, !session.slots.isEmpty {
            statusLine = "Playing \(session.slots.count) stream(s) · \(session.layout)"
            lastError = nil
        } else {
            statusLine = idleStatus()
        }
    }

    func reportPlaybackError(_ message: String) {
        lastError = message
        statusLine = message
    }

    private func restartServer() {
        server?.stop()
        let control = ControlServer(port: UInt16(port), authToken: authToken) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .session(let s):
                    self.applySession(s)
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
            statusLine = idleStatus()
            lastError = nil
        } catch {
            statusLine = "Control API failed: \(error.localizedDescription)"
            lastError = statusLine
        }
    }

    private func idleStatus() -> String {
        let hosts = localAddresses.isEmpty ? ["<no LAN IP>"] : localAddresses
        let list = hosts.map { "\($0):\(port)" }.joined(separator: ", ")
        return "Control API on \(list). Waiting for TVMaestro…"
    }
}
