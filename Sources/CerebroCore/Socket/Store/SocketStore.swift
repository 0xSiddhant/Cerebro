import Foundation

/// Holds the session's sockets. It's an actor because capture arrives on arbitrary threads.
public actor SocketStore {
    private struct Entry {
        var connection: SocketConnection
        var timeline: RingBuffer<SocketTimelineItem>
        var storedBytes = 0
    }

    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private var leastRecentFirst: [UUID] = []
    private var changed = Set<UUID>()
    private var storedBytes = 0
    private var observers = SnapshotObservers<[SocketConnection]>()
    private var pendingPublish: Task<Void, Never>?
    private let frameLimit: Int
    private let connectionLimit: Int
    private let payloadByteLimit: Int
    private let updateInterval: Duration

    /// Creates a store. `frameLimit` caps each socket, and the other two cap the store as a whole,
    /// because a reconnecting socket would otherwise fill a fresh timeline every time.
    public init(
        frameLimit: Int,
        connectionLimit: Int = 100,
        payloadByteLimit: Int,
        updateInterval: Duration = .milliseconds(250)
    ) {
        self.frameLimit = frameLimit
        self.connectionLimit = max(connectionLimit, 1)
        self.payloadByteLimit = payloadByteLimit
        self.updateInterval = updateInterval
    }

    /// The sockets, oldest first.
    public var connections: [SocketConnection] {
        snapshot()
    }

    /// Delivers the current sockets now, then again after each batch of changes.
    public func updates() -> AsyncStream<[SocketConnection]> {
        observers.add(startingWith: snapshot()) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    func record(_ item: SocketTimelineItem, on socket: SocketIdentity) {
        if entries[socket.id] == nil {
            add(socket, startingAt: item.date)
        }
        entries[socket.id]?.connection.apply(item)
        markActive(socket.id)
        append(item, to: socket.id)
        evictOverByteLimit()
        changed.insert(socket.id)
        schedulePublish()
    }

    private func add(_ socket: SocketIdentity, startingAt date: Date) {
        let connection = SocketConnection(id: socket.id, source: socket.source, name: socket.name, startDate: date)
        entries[socket.id] = Entry(connection: connection, timeline: RingBuffer(capacity: frameLimit))
        order.append(socket.id)
        leastRecentFirst.append(socket.id)
        guard order.count > connectionLimit else { return }
        let dropped = leastRecentFirst.removeFirst()
        order.removeAll { $0 == dropped }
        storedBytes -= entries.removeValue(forKey: dropped)?.storedBytes ?? 0
        changed.remove(dropped)
    }

    private func markActive(_ id: UUID) {
        guard leastRecentFirst.last != id else { return }
        leastRecentFirst.removeAll { $0 == id }
        leastRecentFirst.append(id)
    }

    private func append(_ item: SocketTimelineItem, to id: UUID) {
        let added = item.storedBytes
        let evicted = entries[id]?.timeline.append(item)?.storedBytes ?? 0
        entries[id]?.storedBytes += added - evicted
        storedBytes += added - evicted
    }

    /// Takes from the socket idle longest first, so the one in use keeps its history longest.
    private func evictOverByteLimit() {
        var index = 0
        while storedBytes > payloadByteLimit, index < leastRecentFirst.count {
            let id = leastRecentFirst[index]
            guard let removed = entries[id]?.timeline.removeOldest() else {
                index += 1
                continue
            }
            entries[id]?.storedBytes -= removed.storedBytes
            storedBytes -= removed.storedBytes
            changed.insert(id)
        }
    }

    /// Only rebuilds the timelines that changed, because most sockets are idle at any moment.
    private func snapshot() -> [SocketConnection] {
        for id in changed {
            if let timeline = entries[id]?.timeline.elements {
                entries[id]?.connection.timeline = timeline
            }
        }
        changed.removeAll()
        return order.compactMap { entries[$0]?.connection }
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
        guard !observers.isEmpty else { return }
        observers.publish(snapshot())
    }
}

extension SocketTimelineItem {
    fileprivate var storedBytes: Int {
        guard case .frame(let frame) = self, let payload = frame.payload else { return 0 }
        return (payload.data?.count ?? 0) + (payload.rawData?.count ?? 0)
    }
}

extension SocketConnection {
    /// A failed connection stays failed when the app then cancels it, and the reverse.
    fileprivate var isFinished: Bool {
        status == .closed || status == .failed
    }

    /// Totals live here rather than in the timeline, so they stay true after frames are evicted.
    fileprivate mutating func apply(_ item: SocketTimelineItem) {
        switch item {
        case .frame(let frame):
            frameCount += 1
            guard !frame.didFail else { return }
            if frame.direction == .sent {
                bytesSent += Int64(frame.byteCount)
            } else {
                bytesReceived += Int64(frame.byteCount)
            }
            if status == .connecting {
                status = .open
            }
        case .event(.opened, _):
            status = .open
        case .event(.closed, _) where !isFinished:
            status = .closed
        case .event(.failed, _) where !isFinished:
            status = .failed
        case .event:
            break
        }
    }
}
