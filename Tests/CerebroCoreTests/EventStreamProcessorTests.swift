import Foundation
import Testing
import os
@testable import CerebroCore

/// A processor over a real store, with the flushes it asked for recorded in place of a timer.
private struct Pipeline {
    let store: TransactionStore
    let flushes = OSAllocatedUnfairLock<[UUID]>(initialState: [])
    let logged = OSAllocatedUnfairLock<[String]>(initialState: [])
    let backlog = CaptureBacklog(byteLimit: 1_000_000)
    let id = UUID()
    var processor: EventStreamProcessor

    init(requestLimit: Int = 10, jsonKeys: Set<String> = []) {
        let store = TransactionStore(requestLimit: requestLimit)
        let redactor = Redactor(rules: RedactionRules(jsonKeys: jsonKeys))
        let builder = TransactionBuilder(
            processor: BodyProcessor(limit: 100_000, decoders: [], redactor: redactor), redactor: redactor)
        self.store = store
        processor = EventStreamProcessor(
            builder: builder,
            store: store,
            console: ConsoleLogger(level: .full) { [logged] line in logged.withLock { $0.append(line) } },
            scheduleFlush: { [flushes] id in flushes.withLock { $0.append(id) } }
        )
    }

    func exchange(error: (any Error)? = nil) throws -> RawExchange {
        let url = try #require(URL(string: "https://example.com/feed"))
        let headers = ["Content-Type": "text/event-stream"]
        return RawExchange(
            id: id,
            request: URLRequest(url: url),
            requestBody: nil,
            response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers),
            responseBody: nil,
            error: error,
            metrics: nil,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 50),
            isEventStream: true
        )
    }

    mutating func send(_ content: RawStreamActivity.Content, at second: TimeInterval = 1) async {
        await processor.handle(RawStreamActivity(id: id, content: content, date: Date(timeIntervalSince1970: second)))
    }

    mutating func send(_ text: String, at second: TimeInterval = 1) async {
        let data = Data(text.utf8)
        _ = backlog.admit(bytes: data.count)
        await send(.chunk(data, backlog: backlog), at: second)
    }

    var stream: CapturedEventStream? {
        get async { await store.transactions.first { $0.id == id }?.eventStream }
    }
}

@Suite struct EventStreamProcessorTests {
    @Test func theRequestIsStoredAsSoonAsItsResponseArrives() async throws {
        var pipeline = Pipeline()

        await pipeline.send(.opened(try pipeline.exchange()))

        let transaction = try #require(await pipeline.store.transactions.first)
        #expect(transaction.id == pipeline.id)
        #expect(transaction.isOpen)
        #expect(transaction.response?.statusCode == 200)
        #expect(transaction.response?.body == nil)
        #expect(transaction.eventStream?.eventCount == 0)
        #expect(pipeline.flushes.withLock { $0 }.isEmpty)
    }

    @Test func theFirstEventPublishesAtOnceAndTheRestWaitForTheFlush() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))

        await pipeline.send("data: one\n\n", at: 2)
        #expect(await pipeline.stream?.eventCount == 1)
        #expect(pipeline.flushes.withLock { $0 } == [pipeline.id])

        await pipeline.send("data: two\n\n", at: 3)
        await pipeline.send("data: three\n\n", at: 4)
        #expect(await pipeline.stream?.eventCount == 1)
        #expect(pipeline.flushes.withLock { $0 }.count == 1)

        await pipeline.send(.flush)
        #expect(await pipeline.stream?.eventCount == 3)
        #expect(await pipeline.store.transactions.count == 1)
        #expect(await pipeline.store.transactions.first?.response?.endDate == Date(timeIntervalSince1970: 4))
    }

    @Test func aQuietStreamStopsAskingForFlushes() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: one\n\n")

        await pipeline.send(.flush)
        await pipeline.send(": keep-alive\n\n")

        #expect(pipeline.flushes.withLock { $0 }.count == 1)
    }

    @Test func finishingAppliesEveryEventAndLogsOnce() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: one\n\n")
        await pipeline.send("data: two\n\n")

        // No flush ran, so the second event has only reached the store if finishing carried it.
        await pipeline.send(.finished(try pipeline.exchange()))

        let transaction = try #require(await pipeline.store.transactions.first)
        #expect(await pipeline.store.transactions.count == 1)
        #expect(transaction.eventStream?.state == .completed)
        #expect(transaction.eventStream?.eventCount == 2)
        #expect(transaction.response?.endDate == Date(timeIntervalSince1970: 50))
        let lines = pipeline.logged.withLock { $0 }
        #expect(lines.count == 2)
        #expect(lines.last?.contains("Events (2):") == true)
    }

    @Test func aFailureFinishesTheSameTransaction() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: one\n\n")

        await pipeline.send(.finished(try pipeline.exchange(error: URLError(.networkConnectionLost))))

        let transactions = await pipeline.store.transactions
        #expect(transactions.count == 1)
        #expect(transactions.first?.outcome == .failed)
        #expect(transactions.first?.isOpen == false)
        #expect(transactions.first?.eventStream?.eventCount == 1)
    }

    @Test func overflowingMarksTheStreamAndItStillFinishes() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: one\n\n")

        await pipeline.send(.overflowed)
        await pipeline.send("data: lost\n\n")
        await pipeline.send(.finished(try pipeline.exchange()))

        let stream = try #require(await pipeline.stream)
        #expect(stream.state == .completed)
        #expect(stream.eventCount == 1)
        #expect(stream.isTruncated)
    }

    @Test func parsedBytesAreGivenBackToTheBacklog() async throws {
        var pipeline = Pipeline()
        let backlog = CaptureBacklog(byteLimit: 10)
        let data = Data("data: 1\n\n".utf8)
        #expect(backlog.admit(bytes: data.count))
        #expect(!backlog.admit(bytes: data.count))

        // Even for a stream the processor doesn't know, or the budget would leak.
        await pipeline.send(.chunk(data, backlog: backlog))

        #expect(backlog.admit(bytes: data.count))
    }

    @Test func aStreamTheStoreDroppedIsNeverPutBack() async throws {
        var pipeline = Pipeline(requestLimit: 1)
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.store.append(Fixtures.transaction(path: "/newer"))

        await pipeline.send("data: one\n\n")
        await pipeline.send(.finished(try pipeline.exchange()))

        #expect(await pipeline.store.transactions.map { $0.request.url?.path } == ["/newer"])
        #expect(pipeline.logged.withLock { $0 }.isEmpty)
    }

    @Test func aStreamClearedWhileLiveComesBackWithOnlyWhatArrivesAfter() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: before\n\n", at: 1)
        await pipeline.send(.flush)
        await pipeline.store.removeAll()
        let afterClear = Date().timeIntervalSince1970 + 60

        await pipeline.send("data: after\n\n", at: afterClear)

        let stream = try #require(await pipeline.stream)
        #expect(stream.state == .open)
        #expect(stream.eventCount == 1)
        #expect(stream.events.first?.data.data == Data("after".utf8))

        await pipeline.send(.finished(try pipeline.exchange()))
        #expect(await pipeline.stream?.state == .completed)
        #expect(await pipeline.store.transactions.count == 1)
    }

    @Test func aClearedStreamThatEndsWithNothingNewStaysGone() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: before\n\n", at: 1)
        await pipeline.store.removeAll()

        await pipeline.send(.finished(try pipeline.exchange()))

        #expect(await pipeline.store.transactions.isEmpty)
        #expect(pipeline.logged.withLock { $0 }.isEmpty)
    }

    @Test func aClearedStreamThatEndsWithUnpublishedEventsIsStoredWithThem() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: before\n\n", at: 1)
        await pipeline.store.removeAll()
        // Waiting for a flush that never comes, so only finishing can carry it.
        await pipeline.send("data: after\n\n", at: Date().timeIntervalSince1970 + 60)

        await pipeline.send(.finished(try pipeline.exchange()))

        let stream = try #require(await pipeline.stream)
        #expect(stream.state == .completed)
        #expect(stream.events.map(\.data.data) == [Data("after".utf8)])
        #expect(pipeline.logged.withLock { $0 }.count == 2)
    }

    @Test func stoppingClosesEveryStreamStillOpen() async throws {
        var pipeline = Pipeline()
        await pipeline.send(.opened(try pipeline.exchange()))
        await pipeline.send("data: one\n\n", at: 7)

        await pipeline.processor.finishAll()

        let transaction = try #require(await pipeline.store.transactions.first)
        #expect(transaction.eventStream?.state == .completed)
        #expect(transaction.eventStream?.eventCount == 1)
        #expect(transaction.response?.endDate == Date(timeIntervalSince1970: 7))
        // Its real end can't arrive any more, and if it did it would change nothing.
        await pipeline.send(.finished(try pipeline.exchange(error: URLError(.cancelled))))
        #expect(await pipeline.store.transactions.first == transaction)
    }

    @Test func liveUpdatesAreRedactedBeforeTheyReachTheStore() async throws {
        var pipeline = Pipeline(jsonKeys: ["token"])
        await pipeline.send(.opened(try pipeline.exchange()))

        await pipeline.send(#"data: {"token":"s3cret"}"# + "\n\n")

        let stored = try #require(await pipeline.stream?.events.first?.data.data)
        #expect(String(data: stored, encoding: .utf8) == #"{"token":"[redacted]"}"#)
    }
}
