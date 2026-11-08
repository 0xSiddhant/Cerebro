import Foundation
import Testing
@testable import CerebroCore

/// Swizzling is process-wide, so every capture test runs one at a time, across all their suites.
@Suite(.serialized)
enum CaptureTests {}

/// A running capture and a local server for it to talk to.
struct CaptureHarness {
    typealias Handler = @Sendable (LocalHTTPServer.Request) -> LocalHTTPServer.Response

    let runtime: CaptureRuntime
    let server: LocalHTTPServer
    let baseURL: URL

    func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    func transactions(count: Int) async throws -> [HTTPTransaction] {
        for _ in 0..<300 {
            let transactions = await runtime.store.transactions
            if transactions.count >= count {
                return transactions
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await runtime.store.transactions
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
    let runtime = CaptureRuntime(unchecked: configuration)
    runtime.start()
    defer {
        runtime.stop()
        server.stop()
    }
    try await test(CaptureHarness(runtime: runtime, server: server, baseURL: baseURL))
}
