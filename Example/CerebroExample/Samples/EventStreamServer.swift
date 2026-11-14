import Foundation
import Network
import os

/// A small Server-Sent Events server on the loopback interface, so the stream samples work offline and
/// always send the same events. Your app doesn't need anything like this: it's only here to have
/// something to stream from.
///
/// It answers any request with a `text/event-stream` response and reads two query items: `count` for
/// how many events to send, and `interval` for the milliseconds between them.
enum EventStreamServer {
    private struct Running {
        /// Held so the server keeps listening for as long as the app runs.
        let listener: NWListener
        let baseURL: URL
    }

    private static let running = Task { try await start() }

    /// The server's address. The first call starts it.
    static func baseURL() async throws -> URL {
        try await running.value.baseURL
    }

    private static func start() async throws -> Running {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .utility))
            readRequest(from: connection, buffer: Data())
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let result: Result<UInt16, Error>
                switch state {
                case .ready: result = .success(listener.port?.rawValue ?? 0)
                case .failed(let error): result = .failure(error)
                default: return
                }
                let isFirst = hasResumed.withLock { wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if isFirst {
                    continuation.resume(with: result)
                }
            }
            listener.start(queue: .global(qos: .utility))
        }
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else { throw URLError(.badURL) }
        return Running(listener: listener, baseURL: baseURL)
    }

    private static func readRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
                Task { await stream(to: connection, for: head) }
            } else if !isComplete, error == nil {
                readRequest(from: connection, buffer: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private static func stream(to connection: NWConnection, for head: String) async {
        // The request line is `GET /events?count=5&interval=500 HTTP/1.1`.
        let target = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let query = URLComponents(string: target)?.queryItems ?? []
        let count = query.first { $0.name == "count" }?.value.flatMap(Int.init) ?? 5
        let interval = query.first { $0.name == "interval" }?.value.flatMap(Int.init) ?? 500

        // No length and `Connection: close`, so the response lasts until the server closes it.
        let response =
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
            + "Connection: close\r\n\r\n"
        guard await send(response, on: connection) else { return }
        for number in 1...max(count, 1) {
            // Stops as soon as the app cancels the request, which closes the connection.
            guard await send(event(number, of: count), on: connection) else { return }
            try? await Task.sleep(for: .milliseconds(interval))
        }
        connection.cancel()
    }

    /// The events are chosen to show each thing the dashboard does with a stream.
    private static func event(_ number: Int, of count: Int) -> String {
        let id = "id: \(number)\n"
        switch number {
        case count:
            // What many streaming APIs send last. It starts like JSON but isn't, so with `jsonKeys` set
            // in `AppDelegate` it can't be redacted, and the dashboard shows it as withheld.
            return id + "data: [DONE]\n\n"
        case 2:
            // `password` is one of the `jsonKeys` in `AppDelegate`, so the dashboard shows `[redacted]`.
            return id + "event: session\n"
                + #"data: {"user":"demo-user","password":"demo-not-a-real-secret"}"# + "\n\n"
        case 3:
            // Several `data` lines make one event, joined with line breaks. The line that starts with a
            // colon is a comment, which servers send to keep a quiet stream alive, and isn't an event.
            return ": keep-alive\n\n" + id + "event: note\ndata: first line\ndata: second line\n\n"
        default:
            let price = String(format: "%.2f", 120 + Double(number) * 0.25)
            return id + "event: price\n" + #"data: {"symbol":"CRBR","price":\#(price)}"# + "\n\n"
        }
    }

    /// Returns whether the bytes were sent, which they aren't once the app has closed the connection.
    private static func send(_ text: String, on connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(
                content: Data(text.utf8),
                completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                    }
                    continuation.resume(returning: error == nil)
                })
        }
    }
}
