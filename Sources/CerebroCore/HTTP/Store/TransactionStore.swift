import Foundation

/// Holds the session's transactions. It's an actor because capture finishes on arbitrary threads.
public actor TransactionStore {
    /// What became of an update to a transaction that was already stored.
    enum UpdateResult: Equatable {
        /// It replaced the stored transaction.
        case updated

        /// The store dropped the transaction to make room, and it's never put back.
        case evicted

        /// The list was cleared at this time while the transaction was open. Nothing was stored, so
        /// the caller can add it again with only what arrived since.
        case cleared(Date)
    }

    private var buffer: RingBuffer<HTTPTransaction>
    private var runningTotals = SessionTotals()
    private var observers = SnapshotObservers<[HTTPTransaction]>()
    private var requestObservers = SnapshotObservers<[HTTPTransaction]>()
    private let updateInterval: Duration

    /// The streams that were open when the list was cleared, and when that was.
    private var clearedWhileOpen: [UUID: Date] = [:]

    /// Where each change is also written, so the session survives a relaunch. `nil` for a store that
    /// only shows a saved session.
    private let journal: (@Sendable (SessionRecord) -> Void)?

    /// Creates a store. Changes publish at most once per `updateInterval`, so a burst can't flood the UI.
    public init(requestLimit: Int, updateInterval: Duration = .milliseconds(250)) {
        buffer = RingBuffer(capacity: requestLimit)
        self.updateInterval = updateInterval
        journal = nil
    }

    init(requestLimit: Int, journal: (@Sendable (SessionRecord) -> Void)?) {
        buffer = RingBuffer(capacity: requestLimit)
        updateInterval = .milliseconds(250)
        self.journal = journal
    }

    /// The transactions, oldest first.
    public var transactions: [HTTPTransaction] {
        buffer.elements
    }

    /// Bytes moved by every request added this session, including ones the store has since dropped.
    public var totals: SessionTotals {
        runningTotals
    }

    /// Adds a transaction, dropping the oldest if the store is full. An event stream that's still open
    /// is added too, and `update` then keeps it current.
    public func append(_ transaction: HTTPTransaction) {
        buffer.append(transaction)
        runningTotals.add(transaction)
        // Only finished requests are saved, so an open stream waits for the update that ends it.
        if !transaction.isOpen {
            journal?(.http(transaction))
        }
        schedulePublish()
        scheduleRequestPublish()
    }

    /// Replaces the transaction with the same ID, for an event stream that got more events or ended.
    /// If the store no longer holds it, nothing is stored and the result says why.
    @discardableResult
    func update(_ transaction: HTTPTransaction) -> UpdateResult {
        guard let previous = buffer.replaceLast(where: { $0.id == transaction.id }, with: transaction) else {
            return clearedWhileOpen.removeValue(forKey: transaction.id).map(UpdateResult.cleared) ?? .evicted
        }
        if previous.size == nil {
            runningTotals.addBytes(of: transaction)
        }
        if previous.isOpen, !transaction.isOpen {
            journal?(.http(transaction))
        }
        // The list of requests is the same, so readers of `requestUpdates` aren't woken.
        schedulePublish()
        return .updated
    }

    /// Removes every transaction and starts the totals again, as if the session had just begun. Readers
    /// are told at once, not with the next batch, because someone asked for this and is watching.
    public func removeAll() {
        let now = Date()
        for transaction in buffer.elements where transaction.isOpen {
            clearedWhileOpen[transaction.id] = now
        }
        buffer.removeAll()
        runningTotals = SessionTotals()
        journal?(.httpCleared)
        publish()
        publishRequests()
    }

    /// Delivers the current transactions now, then again after each batch of changes.
    /// A slow reader only ever sees the latest batch.
    public func updates() -> AsyncStream<[HTTPTransaction]> {
        observers.add(startingWith: buffer.elements) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    /// The same as `updates`, but only after a request is added or removed. A reader that just counts
    /// requests uses this, so an open event stream's new events never wake it.
    public func requestUpdates() -> AsyncStream<[HTTPTransaction]> {
        requestObservers.add(startingWith: buffer.elements) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    private func removeObserver(_ id: UUID) {
        observers.remove(id)
        requestObservers.remove(id)
    }

    private func schedulePublish() {
        observers.schedulePublish(after: updateInterval) { [weak self] in await self?.publish() }
    }

    private func publish() {
        observers.publish(buffer.elements)
    }

    private func scheduleRequestPublish() {
        requestObservers.schedulePublish(after: updateInterval) { [weak self] in await self?.publishRequests() }
    }

    private func publishRequests() {
        requestObservers.publish(buffer.elements)
    }
}
