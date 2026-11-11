import Foundation
import Testing
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
    try await Task.sleep(for: .milliseconds(600))
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
