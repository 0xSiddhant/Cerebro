import Foundation
import SwiftProtobuf

/// One kind of traffic Cerebro has to capture.
enum TrafficSample: CaseIterable, Sendable {
    case urlSession
    case sharedSession
    case gzip
    case serverError
    case webSocket
    case nwConnection
    case protobuf

    private static let session = URLSession(configuration: .default)

    var title: String {
        switch self {
        case .urlSession: "URLSession"
        case .sharedSession: "URLSession.shared"
        case .gzip: "Gzip response"
        case .serverError: "Server error"
        case .webSocket: "URLSessionWebSocketTask"
        case .nwConnection: "NWConnection"
        case .protobuf: "Protobuf over HTTP"
        }
    }

    /// Sends the traffic and returns a one-line result.
    func run() async throws -> String {
        switch self {
        case .urlSession: try await sendRequest(to: "https://httpbin.org/get", through: Self.session)
        case .sharedSession: try await sendRequest(to: "https://httpbin.org/anything/shared", through: .shared)
        case .gzip: try await sendRequest(to: "https://httpbin.org/gzip", through: Self.session)
        case .serverError: try await sendRequest(to: "https://httpbin.org/status/500", through: Self.session)
        case .webSocket: try await exchangeWebSocketMessage()
        case .nwConnection: try await NWConnectionExchange().run()
        case .protobuf: try await sendProtobuf()
        }
    }

    private func sendRequest(to address: String, through session: URLSession) async throws -> String {
        let (_, response) = try await session.data(from: Self.url(address))
        return Self.summary(of: response)
    }

    private func exchangeWebSocketMessage() async throws -> String {
        let task = Self.session.webSocketTask(with: try Self.url("wss://ws.postman-echo.com/raw"))
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.string("hello from Cerebro"))

        switch try await task.receive() {
        case .string(let text): return "Echo: \(text)"
        case .data(let data): return "Echo: \(data.count) bytes"
        @unknown default: return "Echo: unknown message"
        }
    }

    private func sendProtobuf() async throws -> String {
        var message = Google_Protobuf_Struct()
        message.fields["greeting"] = Google_Protobuf_Value(stringValue: "hello from Cerebro")

        var request = URLRequest(url: try Self.url("https://httpbin.org/post"))
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.httpBody = try message.serializedData()

        let (_, response) = try await Self.session.data(for: request)
        return Self.summary(of: response)
    }

    private static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw URLError(.badURL) }
        return url
    }

    private static func summary(of response: URLResponse) -> String {
        guard let response = response as? HTTPURLResponse else { return "Not an HTTP response" }
        return "HTTP \(response.statusCode)"
    }
}
