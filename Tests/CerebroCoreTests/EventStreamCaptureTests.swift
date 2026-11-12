import Foundation
import Testing
import os
@testable import CerebroCore

/// Holds a test server's response open until the test lets it end.
private final class Gate: Sendable {
    private let isOpen = OSAllocatedUnfairLock(initialState: false)

    func open() {
        isOpen.withLock { $0 = true }
    }

    func wait() async {
        while !isOpen.withLock({ $0 }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A delegate-based client, which gets the response in the pieces URLSession delivers.
private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var data = Data()
        var isFinished = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var text: String {
        state.withLock { String(data: $0.data, encoding: .utf8) ?? "" }
    }

    var isFinished: Bool {
        state.withLock { $0.isFinished }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        state.withLock { $0.data.append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        state.withLock { $0.isFinished = true }
    }
}

private func feed(
    _ pieces: [String],
    contentType: String = "text/event-stream",
    status: Int = 200,
    hold gate: Gate? = nil,
    endsAbruptly: Bool = false
) -> CaptureHarness.Handler {
    { _ in
        LocalHTTPServer.Response(
            status: status,
            headers: ["Content-Type": contentType],
            stream: LocalHTTPServer.Stream(
                pieces: pieces.map { Data($0.utf8) },
                hold: gate.map { gate in { await gate.wait() } },
                endsAbruptly: endsAbruptly
            )
        )
    }
}

private func eventually(_ condition: @Sendable () -> Bool) async throws {
    for _ in 0..<1_500 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

private func texts(of transaction: HTTPTransaction) -> [String?] {
    transaction.eventStream?.events.map { event in event.data.data.flatMap { String(data: $0, encoding: .utf8) } } ?? []
}

extension CaptureTests {
    @Suite struct EventStreams {
        @Test func aStreamShowsItsEventsWhileOpenAndFinishesAsTheSameTransaction() async throws {
            let gate = Gate()
            let handler = feed(["id: 1\nevent: tick\ndata: one\n\n", "data: two\n\n"], hold: gate)
            try await withCapture(handler: handler) { harness in
                let (bytes, _) = try await URLSession(configuration: .default).bytes(from: harness.url("/feed"))
                var lines = bytes.lines.makeAsyncIterator()
                var received: [String] = []
                while received.count < 2, let line = try await lines.next() {
                    if line.hasPrefix("data:") {
                        received.append(line)
                    }
                }
                // The app has both events, and the server is still holding the response open.
                #expect(received == ["data: one", "data: two"])

                let live = try await harness.transaction { $0.eventStream?.eventCount == 2 }
                #expect(live.isOpen)
                #expect(live.outcome == .success)
                #expect(texts(of: live) == ["one", "two"])
                #expect(live.eventStream?.events.map(\.type) == ["tick", "message"])
                #expect(live.eventStream?.events.map(\.id) == ["1", "1"])
                #expect(live.response?.body == nil)
                #expect(live.response?.mimeType == "text/event-stream")

                gate.open()
                while try await lines.next() != nil {}

                let finished = try await harness.transaction { $0.eventStream?.state == .completed }
                #expect(finished.id == live.id)
                #expect(finished.failure == nil)
                #expect(texts(of: finished) == ["one", "two"])
                #expect(finished.size != nil)
                #expect(await harness.runtime.store.transactions.count == 1)
            }
        }

        @Test func aDelegateClientAndAPostStartedStreamAreCaptured() async throws {
            let handler = feed(["data: one\n\n", "data: two\n\n"])
            try await withCapture(handler: handler) { harness in
                let collector = Collector()
                let session = URLSession(configuration: .default, delegate: collector, delegateQueue: nil)
                var request = URLRequest(url: harness.url("/chat"))
                request.httpMethod = "POST"
                request.httpBody = Data(#"{"prompt":"hi"}"#.utf8)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                session.dataTask(with: request).resume()
                try await eventually { collector.isFinished }

                #expect(collector.text == "data: one\n\ndata: two\n\n")
                let finished = try await harness.transaction { $0.eventStream?.state == .completed }
                #expect(finished.request.method == "POST")
                #expect(finished.request.body?.data == Data(#"{"prompt":"hi"}"#.utf8))
                #expect(texts(of: finished) == ["one", "two"])
                #expect(await harness.runtime.store.transactions.count == 1)
                session.invalidateAndCancel()
            }
        }

        @Test func theMediaTypeMatchesInAnyCaseAndWithParameters() async throws {
            let handler = feed(["data: one\n\n"], contentType: "Text/Event-Stream; charset=utf-8")
            try await withCapture(handler: handler) { harness in
                _ = try await URLSession(configuration: .default).data(from: harness.url("/feed"))

                let finished = try await harness.transaction { $0.eventStream?.state == .completed }
                #expect(texts(of: finished) == ["one"])
            }
        }

        @Test func cancellingAnOpenStreamFinishesTheSameTransaction() async throws {
            let gate = Gate()
            try await withCapture(handler: feed(["data: one\n\n"], hold: gate)) { harness in
                let session = URLSession(configuration: .default)
                let task = Task { try await session.data(from: harness.url("/feed")) }
                let live = try await harness.transaction { $0.eventStream?.eventCount == 1 }
                #expect(live.isOpen)

                task.cancel()
                _ = await task.result

                let finished = try await harness.transaction { $0.eventStream?.state == .completed }
                gate.open()
                #expect(finished.id == live.id)
                #expect(finished.outcome == .cancelled)
                #expect(texts(of: finished) == ["one"])
                #expect(await harness.runtime.store.transactions.count == 1)
            }
        }

        @Test func aDroppedConnectionFinishesTheSameTransactionAsFailed() async throws {
            let handler = feed(["data: one\n\n"], endsAbruptly: true)
            try await withCapture(handler: handler) { harness in
                await #expect(throws: (any Error).self) {
                    try await URLSession(configuration: .default).data(from: harness.url("/feed"))
                }

                let finished = try await harness.transaction { $0.eventStream?.state == .completed }
                #expect(finished.outcome == .failed)
                #expect(texts(of: finished) == ["one"])
                #expect(await harness.runtime.store.transactions.count == 1)
            }
        }

        @Test func stoppingCaptureClosesAStreamThatIsStillOpen() async throws {
            let gate = Gate()
            try await withCapture(handler: feed(["data: one\n\n"], hold: gate)) { harness in
                let session = URLSession(configuration: .default)
                let task = Task { try await session.data(from: harness.url("/feed")) }
                let live = try await harness.transaction { $0.eventStream?.eventCount == 1 }
                #expect(live.isOpen)

                harness.runtime.stop()

                let closed = try await harness.transaction { $0.eventStream?.state == .completed }
                #expect(closed.id == live.id)
                #expect(closed.eventStream?.eventCount == 1)
                gate.open()
                _ = try await task.value
            }
        }

        @Test func chunksLargerThanTheBodyLimitAreStillReadWhenNothingIsWaiting() async throws {
            // Many small events in pieces that are each several times the limit.
            let piece = (0..<200).map { "data: event \($0)\n\n" }.joined()
            let configuration = CerebroConfiguration(consoleLevel: .off, bodyLimit: 512)
            let gate = Gate()
            try await withCapture(configuration, handler: feed([piece], hold: gate)) { harness in
                let session = URLSession(configuration: .default)
                let task = Task { try await session.data(from: harness.url("/feed")) }

                let live = try await harness.transaction { $0.eventStream?.eventCount == 200 }
                gate.open()
                _ = try await task.value

                // The oldest went at the byte cap, which is the only reason it's marked truncated.
                #expect(texts(of: live).last == "event 199")
                #expect((live.eventStream?.events.count ?? 0) < 200)
            }
        }

        @Test func anEventLargerThanTheBodyLimitStopsParsingAndTheStreamStillFinishes() async throws {
            let piece = "data: \(String(repeating: "x", count: 4_000))\n\n"
            let configuration = CerebroConfiguration(consoleLevel: .off, bodyLimit: 1_000)
            try await withCapture(configuration, handler: feed([piece, piece, piece])) { harness in
                let (data, _) = try await URLSession(configuration: .default).data(from: harness.url("/feed"))

                #expect(data == Data((piece + piece + piece).utf8))
                let finished = try await harness.transaction { $0.eventStream?.state == .completed }
                #expect(finished.eventStream?.isTruncated == true)
                #expect(finished.eventStream?.events.isEmpty == true)
                #expect(finished.failure == nil)
                #expect(await harness.runtime.store.transactions.count == 1)
            }
        }

        @Test func aChunkedResponseOfAnotherTypeKeepsItsBody() async throws {
            let handler = feed(["data: one\n\n", "data: two\n\n"], contentType: "text/plain")
            try await withCapture(handler: handler) { harness in
                _ = try await URLSession(configuration: .default).data(from: harness.url("/plain"))

                let transaction = try await harness.transaction()
                #expect(transaction.eventStream == nil)
                #expect(transaction.response?.body?.data == Data("data: one\n\ndata: two\n\n".utf8))
            }
        }

        @Test func anEventStreamThatIsNotA200KeepsItsBody() async throws {
            let handler = feed(["data: nope\n\n"], status: 503)
            try await withCapture(handler: handler) { harness in
                _ = try await URLSession(configuration: .default).data(from: harness.url("/feed"))

                let transaction = try await harness.transaction()
                #expect(transaction.eventStream == nil)
                #expect(transaction.outcome == .serverError)
                #expect(transaction.response?.body?.data == Data("data: nope\n\n".utf8))
            }
        }

        @Test func configuredKeysNeverShowInLiveUpdatesOrExports() async throws {
            let gate = Gate()
            let pieces = [#"data: {"token":"s3cret","user":"ada"}"# + "\n\n", "id: token-s3cret\ndata: [DONE]\n\n"]
            let configuration = CerebroConfiguration(
                consoleLevel: .off, redaction: RedactionRules(jsonKeys: ["token"]))
            try await withCapture(configuration, handler: feed(pieces, hold: gate)) { harness in
                let session = URLSession(configuration: .default)
                let task = Task { try await session.data(from: harness.url("/feed")) }

                let live = try await harness.transaction { $0.eventStream?.eventCount == 2 }
                #expect(live.isOpen)
                gate.open()
                _ = try await task.value
                let finished = try await harness.transaction { $0.eventStream?.state == .completed }

                for transaction in [live, finished] {
                    #expect(transaction.eventStream?.events.last?.data.content == .withheld)
                    #expect(transaction.eventStream?.events.last?.id == Redactor.marker)
                    let exports = [TransactionExport.json(transaction), TransactionExport.har([transaction])]
                    for export in exports {
                        #expect(!export.contains("s3cret"))
                        #expect(export.contains("ada"))
                    }
                    let saved = try JSONEncoder().encode(SessionRecord.http(transaction))
                    #expect(String(data: saved, encoding: .utf8)?.contains("s3cret") == false)
                }
            }
        }
    }
}
