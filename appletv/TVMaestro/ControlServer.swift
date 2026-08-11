import Foundation
import UIKit

enum ControlEvent {
    case session(PlaybackSession)
    case stopped
    case failed(String)
}

/// Android-compatible control plane on the LAN.
final class ControlServer {
    private let port: UInt16
    private let authToken: String
    private let onEvent: (ControlEvent) -> Void
    private var http: TinyHTTPServer?
    private let lock = NSLock()
    private var current: PlaybackSession?

    /// Apple TV typically handles several AVPlayers; MPEG-TS is unreliable on AVPlayer.
    static let multiviewMax = 4

    init(port: UInt16, authToken: String, onEvent: @escaping (ControlEvent) -> Void) {
        self.port = port
        self.authToken = authToken
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
            "versionName": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            "port": Int(port),
            "hardware": "appletv",
            "board": "appletv",
            "device": device.name,
            "chip_family": "apple",
            "platform": "tvos",
            "capabilities": [
                "multiview_max": Self.multiviewMax,
                "layouts": ["1", "2x1", "1x2", "2x2"],
                "mpeg_ts": false,
                "hls": true,
                "weak_decoder": false,
                "chip_family": "apple",
                "chip_note": "Prefer HLS from Channels DVR; raw MPEG-TS is unreliable on AVPlayer",
                "cec": [
                    "power": false,
                    "volume": true,
                    "mute": true,
                    "method": "avaudio",
                    "power_detail": "tvOS cannot wake/sleep the TV via this client; use the Siri Remote or HDMI-CEC in Apple TV settings",
                ],
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
        onEvent(.session(session))
        if let obj = Self.asJSONObject(session) {
            return Self.json(200, ["success": true, "session": obj])
        }
        return Self.json(200, ["success": true])
    }

    private func stopSession() -> (Int, Data, String) {
        lock.lock()
        current = nil
        lock.unlock()
        onEvent(.stopped)
        return Self.json(200, ["success": true])
    }

    private func handleCec(_ body: Data) -> (Int, Data, String) {
        struct CecBody: Decodable { var action: String? }
        let action = (try? JSONDecoder().decode(CecBody.self, from: body))?.action?.lowercased()
        let caps: [String: Any] = [
            "power": false,
            "volume": true,
            "mute": true,
            "method": "avaudio",
        ]
        let ok: Bool
        switch action {
        case "volume_up", "volume_down", "mute":
            ok = true
        default:
            ok = false
        }
        return Self.json(200, [
            "success": ok,
            "action": action as Any,
            "capabilities": caps,
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
