import Foundation

/// Reports when items are added to, removed from or renamed in a folder, so its screen can reload
/// without polling. It sees the folder's entries, not a file's contents, so a file that only grew
/// isn't reported.
public enum FolderWatcher {
    /// How long changes are gathered into one report, as the stores batch their updates.
    public static let batchInterval = DispatchTimeInterval.milliseconds(250)

    /// One element per batch of changes, until the stream is cancelled or the folder can't be opened.
    public static func changes(
        in folder: URL,
        batchingFor interval: DispatchTimeInterval = Self.batchInterval
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }
            let queue = DispatchQueue(label: "Cerebro.FolderWatcher", qos: .utility)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
            let batch = PendingBatch()
            source.setEventHandler {
                guard !batch.isPending else { return }
                batch.isPending = true
                queue.asyncAfter(deadline: .now() + interval) {
                    batch.isPending = false
                    continuation.yield()
                }
            }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }

    /// Safety for `@unchecked Sendable`: only the watcher's serial queue reads or writes it.
    private final class PendingBatch: @unchecked Sendable {
        var isPending = false
    }
}
