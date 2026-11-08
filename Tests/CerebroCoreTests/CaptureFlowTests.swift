import Foundation
import Testing
import os
@testable import CerebroCore

private final class RefusesRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private final class AnswersLogins: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.useCredential, URLCredential(user: "ada", password: "pw", persistence: .none))
    }
}

private final class BlockingDecoder: BodyDecoder, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let ranOffTheMainThread = OSAllocatedUnfairLock(initialState: false)

    func decode(_ body: Data, context: BodyContext) -> Data? {
        ranOffTheMainThread.withLock { $0 = !Thread.isMainThread }
        release.wait()
        return nil
    }
}

extension CaptureTests {
    @Suite struct Flow {
        @Test func cancelledRequestRecordsAsCancelled() async throws {
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(delay: .seconds(5)) }
            try await withCapture(handler: handler) { harness in
                let session = URLSession(configuration: .default)
                let task = Task { try await session.data(from: harness.url("/slow")) }
                while harness.server.requests.isEmpty {
                    try await Task.sleep(for: .milliseconds(10))
                }

                task.cancel()

                let error = await task.result.failure
                #expect((error as? URLError)?.code == .cancelled)
                #expect(try await harness.transaction().outcome == .cancelled)
            }
        }

        @Test func connectionFailureRecordsAsFailed() async throws {
            try await withCapture { harness in
                harness.server.stop()
                try await Task.sleep(for: .milliseconds(50))

                await #expect(throws: (any Error).self) {
                    try await URLSession(configuration: .default).data(from: harness.url("/gone"))
                }

                let transaction = try await harness.transaction()
                #expect(transaction.outcome == .failed)
                #expect(transaction.failure?.domain == NSURLErrorDomain)
            }
        }

        @Test func redirectIsFollowedAndEachHopIsRecorded() async throws {
            let handler: CaptureHarness.Handler = { request in
                request.path == "/start"
                    ? LocalHTTPServer.Response(status: 302, reason: "Found", headers: ["Location": "/end"])
                    : LocalHTTPServer.Response(body: Data("arrived".utf8))
            }
            try await withCapture(handler: handler) { harness in
                let (data, response) = try await URLSession(configuration: .default).data(from: harness.url("/start"))

                #expect(data == Data("arrived".utf8))
                #expect((response as? HTTPURLResponse)?.statusCode == 200)
                let transactions = try await harness.transactions(count: 2)
                #expect(Set(transactions.compactMap { $0.response?.statusCode }) == [200, 302])
            }
        }

        @Test func appDelegateCanRefuseARedirect() async throws {
            let handler: CaptureHarness.Handler = { _ in
                LocalHTTPServer.Response(status: 302, reason: "Found", headers: ["Location": "/end"])
            }
            try await withCapture(handler: handler) { harness in
                let session = URLSession(configuration: .default, delegate: RefusesRedirects(), delegateQueue: nil)

                let (_, response) = try await session.data(from: harness.url("/start"))

                #expect((response as? HTTPURLResponse)?.statusCode == 302)
                #expect(harness.server.requests.count == 1)
            }
        }

        @Test func httpLoginChallengeGivesTheAppThe401InsteadOfHanging() async throws {
            let handler: CaptureHarness.Handler = { request in
                request.header("Authorization") == nil
                    ? LocalHTTPServer.Response(
                        status: 401,
                        reason: "Unauthorized",
                        headers: ["WWW-Authenticate": "Basic realm=\"test\""]
                    )
                    : LocalHTTPServer.Response(body: Data("welcome".utf8))
            }
            try await withCapture(handler: handler) { harness in
                let session = URLSession(configuration: .ephemeral, delegate: AnswersLogins(), delegateQueue: nil)

                let (_, response) = try await session.data(from: harness.url("/login"))

                #expect((response as? HTTPURLResponse)?.statusCode == 401)
                #expect(try await harness.transaction().outcome == .clientError)
            }
        }

        @Test func appGetsItsResponseWhileThePipelineIsStillBlocked() async throws {
            let gate = BlockingDecoder()
            try await withCapture(CerebroConfiguration(consoleLevel: .off, decoders: [gate])) { harness in
                let (data, _) = try await URLSession(configuration: .default).data(from: harness.url("/fast"))

                // The decoder hasn't been released, so nothing can have reached the store.
                #expect(data == Data("hello".utf8))
                #expect(await harness.runtime.store.transactions.isEmpty)

                gate.release.signal()
                _ = try await harness.transaction()
                #expect(gate.ranOffTheMainThread.withLock { $0 })
            }
        }

        @Test func secretsNeverReachTheStore() async throws {
            let configuration = CerebroConfiguration(
                consoleLevel: .off,
                redaction: RedactionRules(headers: ["X-Api-Key"], jsonKeys: ["password"], queryParameters: ["token"])
            )
            let handler: @Sendable (LocalHTTPServer.Request) -> LocalHTTPServer.Response = { _ in
                LocalHTTPServer.Response(
                    headers: ["Set-Cookie": "session=secret", "Content-Type": "application/json"],
                    body: Data(#"{"password":"secret","name":"ada"}"#.utf8)
                )
            }
            try await withCapture(configuration, handler: handler) { harness in
                var request = URLRequest(
                    url: harness.url("/login").appending(queryItems: [.init(name: "token", value: "secret")]))
                request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
                request.setValue("secret", forHTTPHeaderField: "X-Api-Key")

                _ = try await URLSession(configuration: .default).data(for: request)

                #expect(harness.server.requests.first?.header("Authorization") == "Bearer secret")
                let stored = String(describing: try await harness.transaction())
                #expect(!stored.contains("secret"))
            }
        }
    }
}

extension Result where Failure == any Error {
    fileprivate var failure: (any Error)? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}
