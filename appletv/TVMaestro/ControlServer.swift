import Foundation
import UIKit

enum ControlEvent {
    case session(PlaybackSession, warning: String?)
    case stopped
    case failed(String)
    case guide(registered: Bool, paired: Bool)
}

/// Android-compatible control plane on the LAN.
final class ControlServer {
    private let port: UInt16
    private let authToken: String
    private let audio: AudioController
    private let onEvent: (ControlEvent) -> Void
    private var http: TinyHTTPServer?
    private let lock = NSLock()
    private var current: PlaybackSession?

    static let multiviewMax = 9
    static let versionName =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"

    init(
        port: UInt16,
        authToken: String,
        audio: AudioController,
        onEvent: @escaping (ControlEvent) -> Void
    ) {
        self.port = port
        self.authToken = authToken
        self.audio = audio
        self.onEvent = onEvent
    }

    func start() throws {
        let server = TinyHTTPServer(port: port) { [weak self] method, path, headers, body in
            guard let self else {
                return Self.json(401, ["success": false, "message": "Server stopping"])
            }
            return self.handle(method: method, path: path, headers: headers, body: body)
        }
        try server.start()
        http = server
    }

    func stop() {
        http?.stop()
        http = nil
    }

    var isListening: Bool { http?.isListening ?? false }

    /// Rebind the listener after tvOS suspends the process. Keeps the current session.
    /// A listener that is already accepting connections is left alone — cancelling it
    /// and binding again races the old socket and fails with "address already in use".
    func restartListening() throws {
        if isListening { return }
        http?.stop()
        http = nil
        try start()
    }

    /// Clears the in-memory session from the UI (Menu remote) without requiring a LAN round-trip.
    func clearSessionLocally() {
        lock.lock()
        current = nil
        lock.unlock()
    }

    private func handle(method: String, path: String, headers: [String: String], body: Data) -> (Int, Data, String) {
        if path.hasPrefix("/api/"), path != "/api/health", !authorized(headers) {
            return Self.json(401, ["success": false, "message": "Unauthorized"])
        }

        switch (method.uppercased(), path) {
        case ("GET", "/"):
            return (200, Data("TVMaestro Client".utf8), "text/plain; charset=utf-8")
        case ("GET", "/api/health"):
            return Self.json(200, ["success": true, "message": "TVMaestro Client running"])
        case ("GET", "/api/info"):
            return Self.json(200, deviceInfo())
        case ("GET", "/api/session"):
            return getSession()
        case ("POST", "/api/session"):
            return setSession(body)
        case ("POST", "/api/session/stop"):
            return stopSession()
        case ("POST", "/api/cec"):
            return handleCec(body)
        case ("POST", "/api/guide"):
            return setGuide(body)
        default:
            return (404, Data("Not Found".utf8), "text/plain")
        }
    }

    private func authorized(_ headers: [String: String]) -> Bool {
        if authToken.isEmpty { return true }
        return headers["x-auth-token"] == authToken
    }

    private func deviceInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "model": device.model,
            "manufacturer": "Apple",
            "androidVersion": device.systemVersion,
            "sdkInt": 0,
            "versionName": Self.versionName,
            "port": Int(port),
            "hardware": "appletv",
            "board": "appletv",
            "device": device.name,
            "chip_family": "apple",
            "platform": "tvos",
            "capabilities": [
                "multiview_max": Self.multiviewMax,
                "layouts": ["1", "2x1", "1x2", "2x2", "3x3"],
                "mpeg_ts": true,
                "hls": true,
                "weak_decoder": false,
                "chip_family": "apple",
                "platform": "tvos",
                "chip_note": "Plays the original MPEG-TS stream, including MPEG-2, without transcoding",
                "cec": audio.capabilities(),
            ],
        ]
    }

    private func getSession() -> (Int, Data, String) {
        lock.lock()
        let session = current
        lock.unlock()
        if let session, let obj = Self.asJSONObject(session) {
            return Self.json(200, ["success": true, "session": obj])
        }
        return Self.json(200, ["success": true, "session": NSNull()])
    }

    private func setSession(_ body: Data) -> (Int, Data, String) {
        let decoder = JSONDecoder()
        guard let incoming = try? decoder.decode(PlaybackSession.self, from: body) else {
            return Self.json(400, ["success": false, "message": "Invalid JSON"])
        }

        let playable = incoming.slots.filter(\.isPlayable)
        if playable.isEmpty {
            return Self.json(400, ["success": false, "message": "No playable slots"])
        }
        if playable.count > Self.multiviewMax {
            return Self.json(400, [
                "success": false,
                "message": "This device supports at most \(Self.multiviewMax) simultaneous stream(s)",
                "multiview_max": Self.multiviewMax,
            ])
        }

        let capacity = LayoutGeometry.capacity(incoming.layout)
        var slots = Array(incoming.slots.prefix(capacity))
        while slots.count < capacity {
            slots.append(SessionSlot())
        }
        if let focus = slots.firstIndex(where: { $0.audio && $0.isPlayable })
            ?? slots.firstIndex(where: \.isPlayable)
        {
            for i in slots.indices {
                slots[i].audio = (i == focus) && slots[i].isPlayable
            }
        }

        let session = PlaybackSession(
            id: incoming.id,
            mode: playable.count > 1 ? "multiview" : "single",
            layout: incoming.layout,
            slots: slots
        )
        lock.lock()
        current = session
        lock.unlock()
        onEvent(.session(session, warning: nil))

        var payload: [String: Any] = ["success": true]
        if let obj = Self.asJSONObject(session) {
            payload["session"] = obj
        }
        return Self.json(200, payload)
    }

    private func stopSession() -> (Int, Data, String) {
        lock.lock()
        current = nil
        lock.unlock()
        onEvent(.stopped)
        return Self.json(200, ["success": true])
    }

    private func setGuide(_ body: Data) -> (Int, Data, String) {
        struct GuideBody: Decodable {
            var registered: Bool?
            var paired: Bool?
        }
        let decoded = try? JSONDecoder().decode(GuideBody.self, from: body)
        onEvent(.guide(registered: decoded?.registered ?? true, paired: decoded?.paired ?? false))
        return Self.json(200, ["success": true])
    }

    private func handleCec(_ body: Data) -> (Int, Data, String) {
        struct CecBody: Decodable { var action: String? }
        let action = (try? JSONDecoder().decode(CecBody.self, from: body))?.action?.lowercased()
        let ok: Bool
        switch action {
        case "volume_up", "volume_down", "mute":
            // The guide sends these over Companion, matching the Siri Remote.
            ok = false
        case "power_on", "power_off":
            ok = false
        default:
            ok = false
        }
        return Self.json(200, [
            "success": ok,
            "action": action as Any,
            "capabilities": audio.capabilities(),
        ])
    }

    private static func asJSONObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func json(_ status: Int, _ object: [String: Any]) -> (Int, Data, String) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return (status, data, "application/json")
    }
}
