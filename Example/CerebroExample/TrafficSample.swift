import Cerebro
import Foundation
import SwiftProtobuf

/// One kind of traffic Cerebro has to capture.
enum TrafficSample: CaseIterable, Sendable {
    case urlSession
    case sharedSession
    case gzip
    case serverError
    case mockStocks
    case mockSlowFlights
    case mockUnauthorized
    case mockEcho
    case redaction
    case webSocket
    case nwConnection
    case externalBridge
    case protobuf

    private static let session = URLSession(configuration: .default)
    private static let mockAPI = "https://mock.0xsiddhant.com"

    var title: String {
        switch self {
        case .urlSession: "URLSession"
        case .sharedSession: "URLSession.shared"
        case .gzip: "Gzip response"
        case .serverError: "Server error"
        case .mockStocks: "Mock API: stocks"
        case .mockSlowFlights: "Mock API: slow flights"
        case .mockUnauthorized: "Mock API: unauthorized"
        case .mockEcho: "Mock API: POST echo"
        case .redaction: "Redaction"
        case .webSocket: "URLSessionWebSocketTask"
        case .nwConnection: "NWConnection"
        case .externalBridge: "ExternalNetworkBridge"
        case .protobuf: "Protobuf over HTTP"
        }
    }

    /// Where a sample that's a plain GET sends it.
    private var address: String {
        switch self {
        case .urlSession: "https://httpbin.org/get"
        case .sharedSession: "https://httpbin.org/anything/shared"
        case .gzip: "https://httpbin.org/gzip"
        case .serverError: "https://httpbin.org/status/500"
        case .mockStocks: "\(Self.mockAPI)/api/v1/stocks"
        case .mockSlowFlights: "\(Self.mockAPI)/api/v1/flights?delay=1500"
        case .mockUnauthorized: "\(Self.mockAPI)/api/v1/flights?status=401"
        case .mockEcho, .redaction, .webSocket, .nwConnection, .externalBridge, .protobuf: ""
        }
    }

    /// Sends the traffic and returns a one-line result.
    func run() async throws -> String {
        switch self {
        case .urlSession, .gzip, .serverError, .mockStocks, .mockSlowFlights, .mockUnauthorized:
            try await sendRequest(to: address, through: Self.session)
        case .sharedSession: try await sendRequest(to: address, through: .shared)
        case .mockEcho: try await postToMockEcho()
        case .redaction: try await postFakeSecrets()
        case .webSocket: try await exchangeWebSocketMessage()
        case .nwConnection: try await NWConnectionExchange().run()
        case .externalBridge: logExternalSocket()
        case .protobuf: try await sendProtobuf()
        }
    }

    private func sendRequest(to address: String, through session: URLSession) async throws -> String {
        let (_, response) = try await session.data(from: Self.url(address))
        return Self.summary(of: response)
    }

    private func postToMockEcho() async throws -> String {
        try await post(
            Data(#"{"hello":"from Cerebro","items":[1,2,3]}"#.utf8),
            contentType: "application/json",
            headers: ["X-Cerebro-Demo": "it's a demo"],
            to: "\(Self.mockAPI)/echo?source=cerebro"
        )
    }

    /// Sends a fake secret everywhere the rules in `AppDelegate` look: headers, a query parameter and a
    /// JSON body, at the top level and nested. Open this request in the dashboard to see each one redacted.
    ///
    /// The endpoint returns nothing on purpose. An echo server repeats the values in its response, under
    /// other keys and inside strings, where these rules don't match them.
    private func postFakeSecrets() async throws -> String {
        let secret = "demo-not-a-real-secret"
        return try await post(
            Data(#"{"username":"demo-user","password":"\#(secret)","profile":{"ssn":"\#(secret)"}}"#.utf8),
            contentType: "application/json",
            headers: [
                "Authorization": "Bearer \(secret)",
                "X-Api-Key": secret,
                "X-Cerebro-Example-Session": secret,
            ],
            to: "https://httpbin.org/status/200?token=\(secret)&page=1"
        )
    }

    private func post(
        _ body: Data,
        contentType: String,
        headers: [String: String] = [:],
        to address: String
    ) async throws -> String {
        var request = URLRequest(url: try Self.url(address))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body

        let (_, response) = try await Self.session.data(for: request)
        return Self.summary(of: response)
    }

    private func exchangeWebSocketMessage() async throws -> String {
        let task = Self.session.webSocketTask(with: try Self.url("wss://ws.postman-echo.com/raw"))
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: Data("done".utf8)) }

        try await task.send(.string("hello from Cerebro"))

        let reply = try await task.receive()
        try await sendPing(on: task)

        switch reply {
        case .string(let text): return "Echo: \(text)"
        case .data(let data): return "Echo: \(data.count) bytes"
        @unknown default: return "Echo: unknown message"
        }
    }

    private func sendPing(on task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Stands in for an engine like Starscream, which reports its own traffic with one call each.
    private func logExternalSocket() -> String {
        let socket = ExternalNetworkBridge.Connection(name: "Starscream sample")
        ExternalNetworkBridge.log(.opened, on: socket)
        ExternalNetworkBridge.log(.text(#"{"subscribe":"prices"}"#), .sent, on: socket)
        ExternalNetworkBridge.log(.text(#"{"price":42}"#), .received, on: socket)
        ExternalNetworkBridge.log(.closed(code: 1000, reason: "done"), on: socket)
        return "Logged 2 frames"
    }

    private func sendProtobuf() async throws -> String {
        var message = Google_Protobuf_Struct()
        message.fields["greeting"] = Google_Protobuf_Value(stringValue: "hello from Cerebro")

        return try await post(
            try message.serializedData(),
            contentType: "application/x-protobuf",
            to: "https://httpbin.org/post"
        )
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
