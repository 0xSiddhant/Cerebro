import Foundation
import SwiftProtobuf

/// One kind of traffic Cerebro has to capture.
enum TrafficSample: CaseIterable, Sendable {
    case urlSession
    case webSocket
    case nwConnection
    case protobuf

    private static let session = URLSession(configuration: .default)

    var title: String {
        switch self {
        case .urlSession: "URLSession"
        case .webSocket: "URLSessionWebSocketTask"
        case .nwConnection: "NWConnection"
        case .protobuf: "Protobuf over HTTP"
        }
    }

    /// Sends the traffic and returns a one-line result.
    func run() async throws -> String {
        switch self {
        case .urlSession: try await sendRequest()
        case .webSocket: try await exchangeWebSocketMessage()
        case .nwConnection: try await NWConnectionExchange().run()
        case .protobuf: try await sendProtobuf()
        }
    }

    private func sendRequest() async throws -> String {
        let (_, response) = try await Self.session.data(from: Self.url("https://httpbin.org/get"))
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
