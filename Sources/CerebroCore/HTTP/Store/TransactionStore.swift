import Foundation

/// Holds the session's transactions. It's an actor because capture finishes on arbitrary threads.
public actor TransactionStore {
    private var buffer: RingBuffer<HTTPTransaction>
    private var runningTotals = SessionTotals()
    private var observers = SnapshotObservers<[HTTPTransaction]>()
    private var pendingPublish: Task<Void, Never>?
    private let updateInterval: Duration

    /// Creates a store. Changes publish at most once per `updateInterval`, so a burst can't flood the UI.
    public init(requestLimit: Int, updateInterval: Duration = .milliseconds(250)) {
        buffer = RingBuffer(capacity: requestLimit)
        self.updateInterval = updateInterval
    }

    /// The transactions, oldest first.
    public var transactions: [HTTPTransaction] {
        buffer.elements
    }

    /// Bytes moved by every request added this session, including ones the store has since dropped.
    public var totals: SessionTotals {
        runningTotals
    }

    /// Adds a finished transaction, dropping the oldest if the store is full.
    public func append(_ transaction: HTTPTransaction) {
        buffer.append(transaction)
        runningTotals.add(transaction)
        schedulePublish()
    }

    /// Delivers the current transactions now, then again after each batch of changes.
    /// A slow reader only ever sees the latest batch.
    public func updates() -> AsyncStream<[HTTPTransaction]> {
        observers.add(startingWith: buffer.elements) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    private func removeObserver(_ id: UUID) {
        observers.remove(id)
    }

    private func schedulePublish() {
        guard pendingPublish == nil else { return }
        pendingPublish = Task { [updateInterval] in
            try? await Task.sleep(for: updateInterval)
            publish()
        }
    }

    private func publish() {
        pendingPublish = nil
        observers.publish(buffer.elements)
    }
}
