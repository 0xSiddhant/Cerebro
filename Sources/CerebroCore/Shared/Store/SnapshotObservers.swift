import Foundation

/// The readers of a store, and the batching of what they're sent. Each reader only ever sees the
/// latest batch, so a slow one can't back up.
struct SnapshotObservers<Snapshot: Sendable> {
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]
    private var pendingPublish: Task<Void, Never>?

    var isEmpty: Bool {
        continuations.isEmpty
    }

    /// Adds a reader, which gets `current` at once if there is one. `onEnd` runs when it stops reading.
    mutating func add(
        startingWith current: Snapshot?,
        onEnd: @escaping @Sendable (UUID) -> Void
    ) -> AsyncStream<Snapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Snapshot.self, bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { _ in onEnd(id) }
        if let current {
            continuation.yield(current)
        }
        continuations[id] = continuation
        return stream
    }

    mutating func remove(_ id: UUID) {
        continuations[id] = nil
    }

    /// Runs `publish` once after `interval`, however often this is called before then, so a burst of
    /// changes reaches readers as one batch. Nothing is scheduled while nobody is reading. `publish`
    /// has to end in `publish(_:)`, which is what allows the next batch.
    mutating func schedulePublish(after interval: Duration, _ publish: @escaping @Sendable () async -> Void) {
        guard pendingPublish == nil, !continuations.isEmpty else { return }
        pendingPublish = Task {
            try? await Task.sleep(for: interval)
            await publish()
        }
    }

    /// Sends a snapshot to every reader. It's only built if someone is still reading.
    mutating func publish(_ snapshot: @autoclosure () -> Snapshot) {
        pendingPublish = nil
        guard !continuations.isEmpty else { return }
        let latest = snapshot()
        continuations.values.forEach { $0.yield(latest) }
    }
}
