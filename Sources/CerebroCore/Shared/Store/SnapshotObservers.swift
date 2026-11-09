import Foundation

/// The readers of a store. Each only ever sees the latest batch, so a slow one can't back up.
struct SnapshotObservers<Snapshot: Sendable> {
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]

    var isEmpty: Bool {
        continuations.isEmpty
    }

    /// Adds a reader, which gets `current` at once. `onEnd` runs when it stops reading.
    mutating func add(
        startingWith current: Snapshot,
        onEnd: @escaping @Sendable (UUID) -> Void
    ) -> AsyncStream<Snapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Snapshot.self, bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { _ in onEnd(id) }
        continuation.yield(current)
        continuations[id] = continuation
        return stream
    }

    mutating func remove(_ id: UUID) {
        continuations[id] = nil
    }

    func publish(_ snapshot: Snapshot) {
        continuations.values.forEach { $0.yield(snapshot) }
    }
}
