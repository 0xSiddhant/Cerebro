import Foundation

/// Holds the session's transactions. It's an actor because capture finishes on arbitrary threads.
public actor TransactionStore {
    private var buffer: RingBuffer<HTTPTransaction>
    private var observers: [UUID: AsyncStream<[HTTPTransaction]>.Continuation] = [:]
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

    /// Adds a finished transaction, dropping the oldest if the store is full.
    public func append(_ transaction: HTTPTransaction) {
        buffer.append(transaction)
        schedulePublish()
    }

    /// Delivers the current transactions now, then again after each batch of changes.
    /// A slow reader only ever sees the latest batch.
    public func updates() -> AsyncStream<[HTTPTransaction]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: [HTTPTransaction].self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        continuation.yield(buffer.elements)
        observers[id] = continuation
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
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
        let snapshot = buffer.elements
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }
}
