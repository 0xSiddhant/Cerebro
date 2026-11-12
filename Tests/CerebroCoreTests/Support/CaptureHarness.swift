import Foundation
import Testing
@testable import CerebroCore

/// Swizzling is process-wide, so every capture test runs one at a time, across all their suites.
@Suite(.serialized)
enum CaptureTests {}

/// A running capture and a local server for it to talk to.
struct CaptureHarness {
    typealias Handler = @Sendable (LocalHTTPServer.Request) -> LocalHTTPServer.Response

    /// Up to 15 seconds in steps of 10 ms. Waits end as soon as the result arrives, and capture runs at
    /// low priority, so a busy CI machine can take several seconds to get to it.
    private static let pollAttempts = 1_500

    let runtime: CaptureRuntime
    let server: LocalHTTPServer
    let baseURL: URL

    func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    func transactions(count: Int) async throws -> [HTTPTransaction] {
        for _ in 0..<Self.pollAttempts {
            let transactions = await runtime.store.transactions
            if transactions.count >= count {
                return transactions
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await runtime.store.transactions
    }

    /// Waits for a socket that meets `condition`, since activity reaches the store in the background.
    func socket(where condition: @Sendable (SocketConnection) -> Bool) async throws -> SocketConnection {
        for _ in 0..<Self.pollAttempts {
            if let socket = await runtime.socketStore.connections.first(where: condition) {
                return socket
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let sockets = await runtime.socketStore.connections
        let match = sockets.first(where: condition)
        return try #require(match, "no matching socket in \(sockets)")
    }

    /// Waits for a transaction that meets `condition`, such as an event stream reaching a state.
    func transaction(where condition: @Sendable (HTTPTransaction) -> Bool) async throws -> HTTPTransaction {
        for _ in 0..<Self.pollAttempts {
            if let transaction = await runtime.store.transactions.first(where: condition) {
                return transaction
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let transactions = await runtime.store.transactions
        let match = transactions.first(where: condition)
        return try #require(match, "no matching transaction in \(transactions)")
    }

    func transaction() async throws -> HTTPTransaction {
        try #require(try await transactions(count: 1).first)
    }
}

func withCapture(
    _ configuration: CerebroConfiguration = CerebroConfiguration(consoleLevel: .off),
    handler: @escaping CaptureHarness.Handler = { _ in LocalHTTPServer.Response(body: Data("hello".utf8)) },
    test: (CaptureHarness) async throws -> Void
) async throws {
    let server = try LocalHTTPServer(handler: handler)
    let baseURL = try await server.start()
    // No sessions directory, so tests leave nothing on disk.
    let runtime = CaptureRuntime(unchecked: configuration, sessionsDirectory: nil)
    runtime.start()
    defer {
        runtime.stop()
        server.stop()
    }
    try await test(CaptureHarness(runtime: runtime, server: server, baseURL: baseURL))
}
