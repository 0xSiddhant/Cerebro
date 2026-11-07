import Foundation
import Network
import os

/// A real HTTP/1.1 server on the loopback interface, so tests exercise URLSession end to end.
final class LocalHTTPServer: Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? {
            headers.first { $0.key.lowercased() == name.lowercased() }?.value
        }
    }

    struct Response: Sendable {
        var status = 200
        var reason = "OK"
        var headers: [String: String] = [:]
        var body = Data()
        var delay: Duration = .zero
    }

    private let listener: NWListener
    private let handler: @Sendable (Request) -> Response
    private let received = OSAllocatedUnfairLock<[Request]>(initialState: [])

    init(handler: @escaping @Sendable (Request) -> Response) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
        self.handler = handler
    }

    var requests: [Request] {
        received.withLock { $0 }
    }

    /// Starts listening and returns the server's base URL.
    func start() async throws -> URL {
        let port: UInt16 = await withCheckedContinuation { continuation in
            let listener = listener
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: .global())
                self.read(from: connection, buffer: Data())
            }
            listener.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                let isFirst = resumed.withLock { wasResumed -> Bool in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if isFirst {
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                }
            }
            listener.start(queue: .global())
        }
        return try requireURL("http://127.0.0.1:\(port)")
    }

    func stop() {
        listener.cancel()
    }

    private func read(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let request = Self.parse(buffer) {
                received.withLock { $0.append(request) }
                respond(to: request, on: connection)
            } else if !isComplete, error == nil {
                read(from: connection, buffer: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let response = handler(request)
        var head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        Task {
            try? await Task.sleep(for: response.delay)
            connection.send(
                content: Data(head.utf8) + response.body,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }
    }

    /// Returns a request once all of it has arrived.
    private static func parse(_ buffer: Data) -> Request? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
            let head = String(data: buffer[..<end.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].components(separatedBy: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[String(line[..<colon])] = value
            }
        }
        let request = Request(method: start[0], path: start[1], headers: headers, body: Data(buffer[end.upperBound...]))
        let expected = request.header("Content-Length").flatMap(Int.init) ?? 0
        return request.body.count >= expected ? request : nil
    }
}

private struct InvalidURL: Error {}

private func requireURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else { throw InvalidURL() }
    return url
}
