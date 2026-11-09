import Foundation
import ObjectiveC
import Testing
@testable import CerebroCore

private func until(_ condition: () -> Bool) async throws {
    for _ in 0..<1_500 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Longer than the wait for metrics that come after completion, so a second row would have shown up.
private func letAnyDuplicateArrive() async throws {
    try await Task.sleep(for: .milliseconds(400))
}

private func proxied(_ configuration: URLSessionConfiguration, delegate: AnyObject?) -> URLSession {
    URLSession(
        configuration: configuration,
        delegate: BackgroundSessionProxy(target: delegate),
        delegateQueue: nil
    )
}

private func background() -> URLSessionConfiguration {
    .background(withIdentifier: "cerebro.tests.\(UUID().uuidString)")
}

extension CaptureTests {
    // A process with no app identifier can be turned away by the system's transfer service, so these run
    // the proxy on an ordinary session, which gives real metrics, unless a test is about the hook itself.
    // The configurations are made before capture starts, so the foreground engine doesn't see them too.
    @Suite struct BackgroundSessions {
        @Test func aDownloadBecomesARowWithItsMetricsAndNoBody() async throws {
            let file = Data(repeating: 7, count: 4_096)
            let configuration = URLSessionConfiguration.ephemeral
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(body: file) }
            try await withCapture(handler: handler) { harness in
                let spy = SpyDelegate()
                let session = proxied(configuration, delegate: spy)
                defer { session.invalidateAndCancel() }

                session.downloadTask(with: harness.url("/file")).resume()

                let transaction = try await harness.transaction()
                #expect(transaction.response?.statusCode == 200)
                #expect(transaction.timing != nil)
                #expect(transaction.connection != nil)
                #expect(transaction.size?.wireBodyBytes == 4_096)
                #expect(transaction.request.body == nil)
                let stored = try #require(transaction.response?.body)
                #expect(stored.content == .notStored)
                #expect(stored.byteCount == 4_096)
                try await until { spy.calls.contains("complete") }
                // iOS decides whether the file or the metrics come first, and it differs by session type.
                #expect(spy.calls.sorted() == ["complete", "file:true", "metrics"])
                #expect(spy.calls.last == "complete")
            }
        }

        @Test func anUploadShowsItsBodyAsNotStoredWithItsSize() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            try await withCapture { harness in
                let session = proxied(configuration, delegate: nil)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: harness.url("/upload"))
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

                session.uploadTask(with: request, from: Data(count: 2_048)).resume()

                let transaction = try await harness.transaction()
                #expect(transaction.request.method == "POST")
                let body = try #require(transaction.request.body)
                #expect(body.content == .notStored)
                #expect(body.byteCount == 2_048)
                #expect(body.contentType == "application/octet-stream")
            }
        }

        @Test func anUploadSentTwiceCountsBothAttempts() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            let handler: CaptureHarness.Handler = { request in
                request.path == "/start"
                    ? LocalHTTPServer.Response(status: 307, reason: "Temporary", headers: ["Location": "/end"])
                    : LocalHTTPServer.Response()
            }
            try await withCapture(handler: handler) { harness in
                let session = proxied(configuration, delegate: nil)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: harness.url("/start"))
                request.httpMethod = "POST"

                session.uploadTask(with: request, from: Data(count: 1_000)).resume()

                let transaction = try await harness.transaction()
                #expect(transaction.request.body?.byteCount == 2_000)
            }
        }

        @Test func aRedirectIsOneRowDescribingItsLastHop() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            let handler: CaptureHarness.Handler = { request in
                request.path == "/start"
                    ? LocalHTTPServer.Response(status: 302, reason: "Found", headers: ["Location": "/end"])
                    : LocalHTTPServer.Response(body: Data(count: 32))
            }
            try await withCapture(handler: handler) { harness in
                let session = proxied(configuration, delegate: nil)
                defer { session.invalidateAndCancel() }

                session.downloadTask(with: harness.url("/start")).resume()

                let transaction = try await harness.transaction()
                try await letAnyDuplicateArrive()
                #expect(await harness.runtime.store.transactions.count == 1)
                #expect(transaction.request.url?.path == "/end")
                #expect(transaction.response?.statusCode == 200)
            }
        }

        @Test func aCancelledTransferIsACancelledRow() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(delay: .seconds(5)) }
            try await withCapture(handler: handler) { harness in
                let session = proxied(configuration, delegate: nil)
                defer { session.invalidateAndCancel() }
                let task = session.downloadTask(with: harness.url("/slow"))

                task.resume()
                try await Task.sleep(for: .milliseconds(100))
                task.cancel()

                let transaction = try await harness.transaction()
                #expect(transaction.outcome == .cancelled)
            }
        }

        @Test func theURLAndHeadersAreRedacted() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            let rules = RedactionRules(headers: ["X-Secret"], queryParameters: ["token"])
            try await withCapture(CerebroConfiguration(consoleLevel: .off, redaction: rules)) { harness in
                let session = proxied(configuration, delegate: nil)
                defer { session.invalidateAndCancel() }
                let url = try #require(URL(string: harness.url("/file").absoluteString + "?token=hunter2"))
                var request = URLRequest(url: url)
                request.setValue("hunter2", forHTTPHeaderField: "X-Secret")

                session.downloadTask(with: request).resume()

                let captured = try await harness.transaction().request
                #expect(captured.url?.absoluteString.contains("hunter2") == false)
                #expect(captured.headers.first { $0.name == "X-Secret" }?.value == Redactor.marker)
            }
        }

        @Test(arguments: ["metricsFirst", "completionFirst"])
        func metricsAndCompletionMakeOneRowInEitherOrder(order: String) async throws {
            let configuration = URLSessionConfiguration.ephemeral
            try await withCapture { harness in
                let recorder = TransferRecorder()
                let session = URLSession(configuration: configuration, delegate: recorder, delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let task = session.dataTask(with: harness.url("/file"))
                let metrics = try #require(await recorder.run(task))
                let proxy = BackgroundSessionProxy(target: nil)

                if order == "metricsFirst" {
                    proxy.urlSession(session, task: task, didFinishCollecting: metrics)
                    proxy.urlSession(session, task: task, didCompleteWithError: nil)
                } else {
                    proxy.urlSession(session, task: task, didCompleteWithError: nil)
                    proxy.urlSession(session, task: task, didFinishCollecting: metrics)
                }

                let rows = try await harness.transactions(count: 1)
                try await letAnyDuplicateArrive()
                #expect(await harness.runtime.store.transactions.count == 1)
                #expect(rows.first?.timing != nil)
                #expect(rows.first?.request.startDate == metrics.taskInterval.start)
            }
        }

        @Test func aCompletionWithNoMetricsStillMakesARow() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            try await withCapture { harness in
                let recorder = TransferRecorder()
                let session = URLSession(configuration: configuration, delegate: recorder, delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let task = session.dataTask(with: harness.url("/file"))
                _ = await recorder.run(task)

                BackgroundSessionProxy(target: nil).urlSession(session, task: task, didCompleteWithError: nil)

                let transaction = try await harness.transaction()
                #expect(transaction.timing == nil)
                #expect(transaction.response?.statusCode == 200)
            }
        }

        @Test func afterStoppingTheProxyOnlyForwards() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            try await withCapture { harness in
                let recorder = TransferRecorder()
                let session = URLSession(configuration: configuration, delegate: recorder, delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let task = session.dataTask(with: harness.url("/file"))
                let metrics = try #require(await recorder.run(task))
                let spy = SpyDelegate()
                let proxy = BackgroundSessionProxy(target: spy)
                harness.runtime.stop()

                proxy.urlSession(session, task: task, didFinishCollecting: metrics)
                proxy.urlSession(session, task: task, didCompleteWithError: nil)

                #expect(spy.calls == ["metrics", "complete"])
                try await letAnyDuplicateArrive()
                #expect(await harness.runtime.store.transactions.isEmpty)
            }
        }

        @Test func aDelegateIsReachedBySelectorEvenIfItNeverDeclaredTheProtocol() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            try await withCapture { harness in
                let undeclared = UndeclaredDelegate()
                let session = proxied(configuration, delegate: undeclared)
                defer { session.invalidateAndCancel() }

                session.dataTask(with: harness.url("/file")).resume()

                try await until { undeclared.completions == 1 }
                #expect(undeclared.completions == 1)
            }
        }

        @Test func whatTheProxyDoesntImplementGoesToTheAppsDelegate() {
            let spy = SpyDelegate()
            let proxy = BackgroundSessionProxy(target: spy)
            let download = #selector(URLSessionDownloadDelegate.urlSession(_:downloadTask:didFinishDownloadingTo:))
            let bodyStream = #selector(URLSessionTaskDelegate.urlSession(_:task:needNewBodyStream:))

            #expect(proxy.responds(to: download))
            #expect(proxy.forwardingTarget(for: download) as AnyObject === spy)
            #expect(!proxy.responds(to: bodyStream))
            #expect(proxy.forwardingTarget(for: bodyStream) == nil)
        }

        @Test func aProxyWithNoDelegateIsSafe() {
            let proxy = BackgroundSessionProxy(target: nil)
            let download = #selector(URLSessionDownloadDelegate.urlSession(_:downloadTask:didFinishDownloadingTo:))

            #expect(!proxy.responds(to: download))
            #expect(proxy.forwardingTarget(for: download) == nil)
        }

        @Test func aBackgroundSessionIsCaptured() async throws {
            try await withCapture { harness in
                let session = URLSession(configuration: background(), delegate: SpyDelegate(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }

                session.downloadTask(with: harness.url("/background")).resume()

                // A row whether the transfer service accepted this process or turned it away.
                let transaction = try await harness.transaction()
                #expect(transaction.request.url?.path == "/background")
            }
        }

        @Test func aBackgroundSessionStillReportsTheAppsOwnDelegate() async throws {
            try await withCapture { _ in
                let spy = SpyDelegate()
                let session = URLSession(configuration: background(), delegate: spy, delegateQueue: nil)
                defer { session.invalidateAndCancel() }

                #expect(session.delegate === spy)
            }
        }

        @Test func aBackgroundSessionWithNoDelegateReportsNone() async throws {
            try await withCapture { _ in
                let session = URLSession(configuration: background())
                defer { session.invalidateAndCancel() }

                #expect(session.delegate == nil)
            }
        }

        @Test func otherSessionsGetNoProxy() async throws {
            try await withCapture { _ in
                let spy = SpyDelegate()
                _ = URLSession(configuration: background(), delegate: spy, delegateQueue: nil)
                let session = URLSession(configuration: .default, delegate: spy, delegateQueue: nil)
                defer { session.invalidateAndCancel() }

                // Only a background session's class unwraps a proxy, so this would be one if it had been given it.
                #expect(session.delegate === spy)
            }
        }

        @Test func stoppingRestoresSessionCreation() async throws {
            let selector = NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")
            let metaclass: AnyClass = try #require(object_getClass(URLSession.self))
            let before = class_getMethodImplementation(metaclass, selector)

            try await withCapture { _ in
                #expect(class_getMethodImplementation(metaclass, selector) != before)
            }

            #expect(class_getMethodImplementation(metaclass, selector) == before)
        }
    }
}

@Test func anUncapturedRequestBodyWithNoMetricsHasNoBody() {
    let redactor = Redactor(rules: RedactionRules())
    let builder = TransactionBuilder(
        processor: BodyProcessor(limit: 1_000, decoders: [], redactor: redactor),
        redactor: redactor
    )
    let exchange = RawExchange(
        id: UUID(),
        request: URLRequest(url: URL(fileURLWithPath: "/")),
        requestBody: nil,
        response: nil,
        responseBody: nil,
        error: nil,
        metrics: nil,
        startDate: Date(),
        endDate: Date()
    )

    #expect(builder.transaction(from: exchange).request.body == nil)
}
