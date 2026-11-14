import Foundation

/// A foreground download that's still running. Its body is never stored.
public struct DownloadProgress: Sendable, Equatable, Identifiable {
    /// Identifies the download, and matches the request it becomes once it finishes.
    public let id: UUID

    /// The URL, with matching query parameters redacted.
    public let url: URL?

    /// When the download started.
    public let startDate: Date

    /// Body bytes received so far.
    public var bytesReceived: Int64

    /// The size the server announced, if it did.
    public var expectedBytes: Int64?

    /// The MIME type the server reported.
    public var mimeType: String?

    /// Creates a download.
    public init(
        id: UUID,
        url: URL?,
        startDate: Date,
        bytesReceived: Int64 = 0,
        expectedBytes: Int64? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.url = url
        self.startDate = startDate
        self.bytesReceived = bytesReceived
        self.expectedBytes = expectedBytes
        self.mimeType = mimeType
    }

    /// How much has arrived, from 0 to 1, if the server announced a size.
    public var fractionCompleted: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(Double(bytesReceived) / Double(expectedBytes), 1)
    }
}

/// What capture reports about a download as it runs.
enum DownloadEvent: Sendable {
    case started(id: UUID, url: URL?, date: Date)
    case received(id: UUID, bytes: Int64, expectedBytes: Int64?, mimeType: String?)
    case finished(id: UUID)
}

/// Holds the downloads in flight. Changes publish in batches, because progress moves constantly.
public actor DownloadProgressStore {
    /// More downloads than this at once aren't tracked, so the store can't grow without limit.
    static let limit = 100

    private var downloads: [UUID: DownloadProgress] = [:]
    private var order: [UUID] = []
    private var observers = SnapshotObservers<[DownloadProgress]>()
    private let updateInterval: Duration

    init(updateInterval: Duration = .milliseconds(250)) {
        self.updateInterval = updateInterval
    }

    /// The downloads in flight, oldest first.
    public var active: [DownloadProgress] {
        order.compactMap { downloads[$0] }
    }

    /// Delivers the downloads in flight now, then again after each batch of changes.
    public func updates() -> AsyncStream<[DownloadProgress]> {
        observers.add(startingWith: active) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    func apply(_ event: DownloadEvent) {
        switch event {
        case .started(let id, let url, let date):
            guard downloads[id] == nil, order.count < Self.limit else { return }
            downloads[id] = DownloadProgress(id: id, url: url, startDate: date)
            order.append(id)
        case .received(let id, let bytes, let expectedBytes, let mimeType):
            guard downloads[id] != nil else { return }
            downloads[id]?.bytesReceived = bytes
            downloads[id]?.expectedBytes = expectedBytes
            downloads[id]?.mimeType = mimeType
        case .finished(let id):
            guard downloads.removeValue(forKey: id) != nil else { return }
            order.removeAll { $0 == id }
        }
        schedulePublish()
    }

    private func removeObserver(_ id: UUID) {
        observers.remove(id)
    }

    /// Forgets every download, for when capture stops and no more reports can arrive.
    func removeAll() {
        guard !order.isEmpty else { return }
        downloads.removeAll()
        order.removeAll()
        schedulePublish()
    }

    private func schedulePublish() {
        observers.schedulePublish(after: updateInterval) { [weak self] in await self?.publish() }
    }

    private func publish() {
        observers.publish(active)
    }
}
