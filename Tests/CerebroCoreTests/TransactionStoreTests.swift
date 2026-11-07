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
    let store = TransactionStore(requestLimit: 1_000, updateInterval: .milliseconds(50))
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
    try await Task.sleep(for: .milliseconds(300))
    reader.cancel()

    let batches = await counter.batches
    #expect(batches.count == 2)
    #expect(batches.first?.isEmpty == true)
    #expect(batches.last?.count == 200)
}
