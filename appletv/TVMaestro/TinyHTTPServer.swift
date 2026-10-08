import Foundation
import Network

/// Minimal HTTP/1.1 listener for the TVMaestro control API (no third-party deps).
final class TinyHTTPServer {
    typealias Handler = (_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (status: Int, body: Data, contentType: String)

    private let port: NWEndpoint.Port
    private let handler: Handler
    private var listener: NWListener?
    private var state: NWListener.State = .setup
    private var rebindAttempts = 0
    private let stateLock = NSLock()
    private let queue = DispatchQueue(label: "com.tvmaestro.httpserver")

    /// True while a listener exists and has not failed. `.setup` counts so a
    /// foreground bounce during startup does not cancel a bind still in progress.
    var isListening: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listener != nil else { return false }
        switch state {
        case .ready, .waiting, .setup:
            return true
        default:
            return false
        }
    }

    init(port: UInt16, handler: @escaping Handler) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
    }

    func start() throws {
        rebindAttempts = 0
        try bind()
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        stateLock.lock()
        state = .cancelled
        stateLock.unlock()
    }

    private func bind() throws {
        if let existing = listener {
            existing.stateUpdateHandler = nil
            existing.cancel()
            listener = nil
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] newState in
            self?.handle(newState)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(_ newState: NWListener.State) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
        guard case .failed(let error) = newState else { return }
        NSLog("TVMaestro HTTP listener failed: \(error)")
        let code = (error as NSError).code
        guard code == Int(POSIXError.EADDRINUSE.rawValue), rebindAttempts < 5 else { return }
        rebindAttempts += 1
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            do {
                try self.bind()
            } catch {
                NSLog("TVMaestro HTTP rebind failed: \(error)")
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                NSLog("TVMaestro HTTP receive error: \(error)")
                connection.cancel()
                return
            }
            var buf = buffer
            if let data { buf.append(data) }

            if let request = Self.parseRequest(buf) {
                let response = self.handler(request.method, request.path, request.headers, request.body)
                self.send(response, on: connection)
                return
            }

            if isComplete {
                connection.cancel()
                return
            }
            // Headers incomplete or body still arriving
            if buf.count > 2 * 1024 * 1024 {
                self.send((413, Data("Payload too large".utf8), "text/plain"), on: connection)
                return
            }
            self.receive(on: connection, buffer: buf)
        }
    }

    private func send(_ response: (status: Int, body: Data, contentType: String), on connection: NWConnection) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(response.body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct Parsed {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    private static func parseRequest(_ data: Data) -> Parsed? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1].split(separator: "?").first ?? parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerEnd.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let available = data.count - bodyStart
        guard available >= contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return Parsed(method: method, path: path, headers: headers, body: body)
    }
}
