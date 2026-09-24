import Foundation
import Network

/// A minimal HTTP server bound to 127.0.0.1 that receives Claude Code hook payloads.
///
///   POST /claude-buddy/event   body = hook JSON  → 204
///   GET  /claude-buddy/ping                      → 200 "claude-buddy ok"
final class EventServer {
    static let eventPath = "/claude-buddy/event"
    static let pingPath = "/claude-buddy/ping"

    let port: UInt16
    var onEvent: (([String: Any]) -> Void)?
    private(set) var status = "Starting…"

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "claude-buddy.server")
    private let maxRequestBytes = 32 << 20

    init(port: UInt16) { self.port = port }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let text: String
            switch state {
            case .ready: text = "Listening on 127.0.0.1:\(self.port)"
            case .failed(let error): text = "Server failed: \(error.localizedDescription)"
            default: return
            }
            DispatchQueue.main.async { self.status = text }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(connection, request)
            } else if isComplete || error != nil || buffer.count > self.maxRequestBytes {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let body: Data
    }

    /// Returns a request once the headers and the full Content-Length body have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        let lines = header.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]), body: data[bodyStart..<(bodyStart + length)])
    }

    private func respond(_ connection: NWConnection, _ request: Request) {
        let reply: String
        switch (request.method, request.path) {
        case ("POST", Self.eventPath):
            if let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
                DispatchQueue.main.async { self.onEvent?(json) }
                reply = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
            } else {
                reply = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
        case ("GET", Self.pingPath):
            reply = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\nConnection: close\r\n\r\nclaude-buddy ok"
        default:
            reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
