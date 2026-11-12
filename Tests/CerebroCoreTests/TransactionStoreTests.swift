import Foundation
import Testing
import os
@testable import CerebroCore

private actor Counter {
    private(set) var batches: [[HTTPTransaction]] = []
    func add(_ batch: [HTTPTransaction]) { batches.append(batch) }
}

@Test func requestOverTheLimitEvictsTheOldest() async {
    let store = TransactionStore(requestLimit: 500)
    let all = (0..<501).map { Fixtures.transaction(path: "/\($0)") }

    for transaction in all {
        await store.append(transaction)
    }

    let kept = await store.transactions
    #expect(kept.count == 500)
    #expect(kept.first?.id == all[1].id)
    #expect(kept.last?.id == all[500].id)
}

@Test func newObserverGetsTheCurrentTransactionsAtOnce() async {
    let store = TransactionStore(requestLimit: 10)
    await store.append(Fixtures.transaction())

    var updates = await store.updates().makeAsyncIterator()

    #expect(await updates.next()?.count == 1)
}

@Test func burstOfChangesPublishesOneBatch() async throws {
    let store = TransactionStore(requestLimit: 1_000, updateInterval: .milliseconds(200))
    let counter = Counter()
    let stream = await store.updates()
    let reader = Task {
        for await batch in stream {
            await counter.add(batch)
        }
    }

    for index in 0..<200 {
        await store.append(Fixtures.transaction(path: "/\(index)"))
    }
    // Waits for the batch itself, not a fixed time, because a busy machine can be late delivering it.
    for _ in 0..<1_500 where await counter.batches.last?.count != 200 {
        try await Task.sleep(for: .milliseconds(10))
    }
    reader.cancel()

    // The first delivery is the empty store. A slow machine may split the burst once, but never into 200.
    let batches = await counter.batches
    #expect(batches.count <= 3)
    #expect(batches.first?.isEmpty == true)
    #expect(batches.last?.count == 200)
}

@Test func clearingRemovesEveryRequestAndStartsTheTotalsAgain() async {
    let store = TransactionStore(requestLimit: 10)
    let sized = HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://a.com"), method: "GET", startDate: Date()),
        size: TransferSize(bytesSent: 10, bytesReceived: 100, wireBodyBytes: 0, decodedBodyBytes: 0)
    )
    await store.append(sized)
    await store.append(sized)

    await store.removeAll()

    #expect(await store.transactions.isEmpty)
    #expect(await store.totals == SessionTotals())
}

@Test func clearingTellsReadersAtOnceAndTheStoreKeepsWorking() async throws {
    let store = TransactionStore(requestLimit: 10, updateInterval: .seconds(30))
    await store.append(Fixtures.transaction())
    var updates = await store.updates().makeAsyncIterator()
    #expect(await updates.next()?.count == 1)

    await store.removeAll()

    // The batch interval is 30 s, so this can only arrive because clearing publishes straight away.
    #expect(await updates.next()?.isEmpty == true)
    await store.append(Fixtures.transaction(path: "/after"))
    #expect(await store.transactions.map { $0.request.url?.path } == ["/after"])
    #expect(await store.totals.requestCount == 1)
}

@Test func aClearedBufferFillsAndEvictsAsBefore() {
    var buffer = RingBuffer<Int>(capacity: 2)
    buffer.append(1)
    buffer.append(2)
    buffer.append(3)

    buffer.removeAll()
    #expect(buffer.elements.isEmpty)

    buffer.append(4)
    buffer.append(5)
    buffer.append(6)
    #expect(buffer.elements == [5, 6])
}

// MARK: - Event streams

private final class Journal: Sendable {
    private let stored = OSAllocatedUnfairLock<[SessionRecord]>(initialState: [])

    var transactions: [HTTPTransaction] {
        stored.withLock { records in
            records.compactMap { record in
                if case .http(let transaction) = record { return transaction }
                return nil
            }
        }
    }

    func add(_ record: SessionRecord) {
        stored.withLock { $0.append(record) }
    }
}

@Test func anUpdateReplacesTheSameTransactionInPlace() async {
    let store = TransactionStore(requestLimit: 10)
    let open = Fixtures.stream(.open)
    await store.append(Fixtures.transaction(path: "/before"))
    await store.append(open)
    await store.append(Fixtures.transaction(path: "/after"))

    let updated = Fixtures.stream(id: open.id, .open, events: [Fixtures.event("one")])
    #expect(await store.update(updated) == .updated)

    let kept = await store.transactions
    #expect(kept.count == 3)
    #expect(kept[1] == updated)
    #expect(await store.totals.requestCount == 3)
}

@Test func anUpdateForAnEvictedTransactionIsIgnoredAndNeverPutBack() async {
    let store = TransactionStore(requestLimit: 2)
    let open = Fixtures.stream(.open)
    await store.append(open)
    await store.append(Fixtures.transaction(path: "/a"))
    await store.append(Fixtures.transaction(path: "/b"))

    #expect(await store.update(Fixtures.stream(id: open.id, .completed)) == .evicted)

    #expect(await store.transactions.map { $0.request.url?.path } == ["/a", "/b"])
}

@Test func anUpdateAfterClearingStoresNothingAndSaysWhenTheClearWas() async {
    let store = TransactionStore(requestLimit: 10)
    let open = Fixtures.stream(.open)
    await store.append(open)
    await store.append(Fixtures.transaction())
    let before = Date()
    await store.removeAll()

    let result = await store.update(Fixtures.stream(id: open.id, .open))

    guard case .cleared(let date) = result else {
        Issue.record("expected the clear to be reported, got \(result)")
        return
    }
    #expect(date >= before)
    #expect(await store.transactions.isEmpty)
    // Reported once. After that the stream is the caller's to add again, or it's simply gone.
    #expect(await store.update(Fixtures.stream(id: open.id, .open)) == .evicted)
}

@Test func aStreamsBytesAreCountedOnceWhenItEnds() async {
    let store = TransactionStore(requestLimit: 10)
    let open = Fixtures.stream(.open)
    let size = TransferSize(bytesSent: 10, bytesReceived: 100, wireBodyBytes: 0, decodedBodyBytes: 0)
    await store.append(open)

    await store.update(Fixtures.stream(id: open.id, .completed, size: size))
    await store.update(Fixtures.stream(id: open.id, .completed, size: size))

    let totals = await store.totals
    #expect(totals.requestCount == 1)
    #expect(totals.bytesReceived == 100)
}

@Test func aBurstOfUpdatesPublishesOneBatch() async throws {
    let store = TransactionStore(requestLimit: 10, updateInterval: .milliseconds(200))
    let counter = Counter()
    let open = Fixtures.stream(.open)
    await store.append(open)
    let stream = await store.updates()
    let reader = Task {
        for await batch in stream {
            await counter.add(batch)
        }
    }

    for count in 1...200 {
        let events = (0..<count).map { Fixtures.event(String($0)) }
        await store.update(Fixtures.stream(id: open.id, .open, events: events))
    }
    for _ in 0..<1_500 where await counter.batches.last?.first?.eventStream?.eventCount != 200 {
        try await Task.sleep(for: .milliseconds(10))
    }
    reader.cancel()

    let batches = await counter.batches
    #expect(batches.count <= 3)
    #expect(batches.last?.first?.eventStream?.eventCount == 200)
}

@Test func eventOnlyUpdatesNeverWakeAReaderOfRequests() async throws {
    let store = TransactionStore(requestLimit: 10, updateInterval: .milliseconds(20))
    let counter = Counter()
    let open = Fixtures.stream(.open)
    await store.append(open)
    let stream = await store.requestUpdates()
    let reader = Task {
        for await batch in stream {
            await counter.add(batch)
        }
    }
    var everything = await store.updates().makeAsyncIterator()
    _ = await everything.next()

    await store.update(Fixtures.stream(id: open.id, .open, events: [Fixtures.event("one")]))
    // The other reader getting the update proves the batch went out, so the count below is final.
    #expect(await everything.next()?.first?.eventStream?.eventCount == 1)
    #expect(await counter.batches.count == 1)

    await store.append(Fixtures.transaction(path: "/new"))
    for _ in 0..<1_500 where await counter.batches.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    reader.cancel()

    #expect(await counter.batches.map(\.count) == [1, 2])
}

@Test func onlyAFinishedStreamIsSavedAndOnlyOnce() async {
    let journal = Journal()
    let store = TransactionStore(requestLimit: 10) { journal.add($0) }
    let open = Fixtures.stream(.open)
    await store.append(open)
    await store.update(Fixtures.stream(id: open.id, .open, events: [Fixtures.event("one")]))
    #expect(journal.transactions.isEmpty)

    let finished = Fixtures.stream(id: open.id, .completed, events: [Fixtures.event("one")])
    await store.update(finished)

    #expect(journal.transactions == [finished])
}

@Test func replacingInARingBufferKeepsOrderAcrossTheWrap() {
    var buffer = RingBuffer<Int>(capacity: 3)
    [1, 2, 3, 4].forEach { buffer.append($0) }

    #expect(buffer.replaceLast(where: { $0 == 4 }, with: 40) == 4)
    #expect(buffer.replaceLast(where: { $0 == 2 }, with: 20) == 2)
    #expect(buffer.replaceLast(where: { $0 == 1 }, with: 10) == nil)

    #expect(buffer.elements == [20, 3, 40])
}
