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
    case mockUpload
    case mockPut
    case mockPatch
    case mockDelete
    case redaction
    case eventStream
    case eventStreamLong
    case webSocket
    case nwConnection
    case externalBridge
    case protobuf
    case protobufFromMap
    case backgroundDownload
    case backgroundUpload
    case backgroundLargeDownload

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
        case .mockUpload: "Mock API: upload JSON"
        case .mockPut: "Mock API: PUT blackhole"
        case .mockPatch: "Mock API: PATCH blackhole"
        case .mockDelete: "Mock API: DELETE blackhole"
        case .redaction: "Redaction"
        case .eventStream: "Server-Sent Events"
        case .eventStreamLong: "Server-Sent Events: 1 minute"
        case .webSocket: "URLSessionWebSocketTask"
        case .nwConnection: "NWConnection"
        case .externalBridge: "ExternalNetworkBridge"
        case .protobuf: "Protobuf: code rule"
        case .protobufFromMap: "Protobuf: traffic_map.json"
        case .backgroundDownload: "Background download"
        case .backgroundUpload: "Background upload"
        case .backgroundLargeDownload: "Background download: 100 MB"
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
        case .mockEcho, .mockUpload, .mockPut, .mockPatch, .mockDelete, .redaction, .eventStream, .eventStreamLong,
            .webSocket, .nwConnection, .externalBridge, .protobuf, .protobufFromMap, .backgroundDownload,
            .backgroundUpload, .backgroundLargeDownload:
            ""
        }
    }

    /// Sends the traffic and returns a one-line result.
    func run() async throws -> String {
        switch self {
        case .urlSession, .gzip, .serverError, .mockStocks, .mockSlowFlights, .mockUnauthorized:
            try await sendRequest(to: address, through: Self.session)
        case .sharedSession: try await sendRequest(to: address, through: .shared)
        case .mockEcho: try await postToMockEcho()
        case .mockUpload: try await uploadMockJSON()
        case .mockPut, .mockPatch, .mockDelete: try await sendBlackholeRequest()
        case .redaction: try await postFakeSecrets()
        case .eventStream, .eventStreamLong: try await streamEvents()
        case .webSocket, .nwConnection, .externalBridge: try await useSocket()
        case .protobuf, .protobufFromMap: try await sendProtobuf()
        case .backgroundDownload, .backgroundUpload, .backgroundLargeDownload: try await runBackgroundTransfer()
        }
    }

    private func useSocket() async throws -> String {
        switch self {
        case .webSocket: try await exchangeWebSocketMessage()
        case .nwConnection: try await NWConnectionExchange().run()
        default: logExternalSocket()
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

    private func uploadMockJSON() async throws -> String {
        var request = URLRequest(url: try Self.url("\(Self.mockAPI)/upload"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try sampleJSON()

        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard response.statusCode == 201 else {
            throw MockAPIError.httpStatus(method: "POST", statusCode: response.statusCode)
        }

        let result = try JSONDecoder().decode(MockUploadResponse.self, from: data)
        guard result.success else {
            throw URLError(.badServerResponse)
        }
        return "Mock URL: \(result.data.url)"
    }

    /// The HTTP method and accepted statuses of the blackhole samples, and `nil` for every other sample.
    private var blackholeRequest: (method: String, acceptedStatusCodes: Set<Int>)? {
        switch self {
        case .mockPut: ("PUT", [200, 201, 204])
        case .mockPatch: ("PATCH", [200, 204])
        case .mockDelete: ("DELETE", [200, 202, 204])
        default: nil
        }
    }

    private func sendBlackholeRequest() async throws -> String {
        guard let (method, acceptedStatusCodes) = blackholeRequest else {
            throw URLError(.unsupportedURL)
        }
        var request = URLRequest(url: try Self.url("\(Self.mockAPI)/blackhole"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try sampleJSON()

        let (_, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard acceptedStatusCodes.contains(response.statusCode) else {
            throw MockAPIError.httpStatus(method: method, statusCode: response.statusCode)
        }
        return Self.summary(of: response)
    }

    private func sampleJSON() throws -> Data {
        guard let fileURL = Bundle.main.url(forResource: "mock-request", withExtension: "json") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: fileURL)
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

    private struct MockUploadResponse: Decodable {
        let success: Bool
        let data: MockUploadResult
    }

    private struct MockUploadResult: Decodable {
        let url: URL
    }

    private enum MockAPIError: LocalizedError {
        case httpStatus(method: String, statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let method, let statusCode): "Mock API \(method) failed with HTTP \(statusCode)"
            }
        }
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

        var quote = Market_V1_Quote()
        quote.symbol = "CRBR"
        quote.price = 123.45
        quote.volume = 1_000

        let usesMap = self == .protobufFromMap
        return try await post(
            usesMap ? try quote.serializedData() : try message.serializedData(),
            contentType: "application/x-protobuf",
            to: usesMap ? "https://httpbin.org/anything/quote" : "https://httpbin.org/post"
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

extension TrafficSample {
    /// What the row says before the sample has run, for the ones that don't run at launch.
    var hint: String? {
        switch self {
        case .mockUpload: "Tap to upload sample JSON"
        case .eventStreamLong: "Tap, then open the dashboard to watch it live"
        case .backgroundLargeDownload: "Tap, then leave the app or stop it from Xcode"
        default: nil
        }
    }

    /// The large download takes several seconds, which leaves time to test it. Start it, go to the home screen
    /// and stop the app from Xcode. iOS finishes the transfer, relaunches the app in the background, and
    /// the request is in Cerebro's log when you open the app again. Quitting from the app switcher is
    /// different: iOS cancels the transfer.
    private func runBackgroundTransfer() async throws -> String {
        let response: URLResponse
        switch self {
        case .backgroundUpload:
            response = try await BackgroundTransfers.upload(
                Data(count: 4_096), to: Self.url("https://httpbin.org/post"))
        case .backgroundLargeDownload:
            response = try await BackgroundTransfers.download(from: Self.url("https://proof.ovh.net/files/100Mb.dat"))
        default:
            response = try await BackgroundTransfers.download(from: Self.url("https://httpbin.org/bytes/2048"))
        }
        return Self.summary(of: response)
    }

    /// Reads a Server-Sent Events stream to its end, the way an app usually does, with `bytes(for:)`.
    /// Cerebro needs nothing extra: the request joins the HTTP list as soon as its response arrives, and
    /// its page lists each event as it comes in. `EventStreamServer` says what the events show.
    private func streamEvents() async throws -> String {
        // Five events in a few seconds at launch, or one a second for a minute, to watch it live.
        let (count, milliseconds) = self == .eventStreamLong ? (60, 1_000) : (5, 500)
        let query = [
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "interval", value: String(milliseconds)),
        ]
        let url = try await EventStreamServer.baseURL().appending(path: "events").appending(queryItems: query)
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await Self.session.bytes(for: request)
        var events = 0
        // Every event the server sends has one `id` line.
        for try await line in bytes.lines where line.hasPrefix("id:") {
            events += 1
        }
        return "\(Self.summary(of: response)), \(events) events"
    }
}
