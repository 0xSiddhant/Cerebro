import Foundation

/// One line of a session's file.
enum SessionRecord: Sendable, Codable {
    case header(version: Int, startDate: Date)
    case http(HTTPTransaction)

    /// The HTTP list was cleared, so the requests before this line no longer count.
    case httpCleared
    case socket(SocketIdentity, SocketTimelineItem)
}

/// A session saved by an earlier launch.
public struct StoredSessionReference: Sendable, Equatable, Identifiable {
    /// The session's file.
    public let id: URL

    /// When that launch started capturing.
    public let startDate: Date
}

/// A saved session, read back into stores of its own so the same screens can show it. Nothing writes to
/// these stores, which is what makes the view read-only.
public struct StoredSession: Sendable {
    /// Which session this is.
    public let reference: StoredSessionReference

    /// Its HTTP requests.
    public let store: TransactionStore

    /// Its sockets.
    public let socketStore: SocketStore
}

/// Keeps each session on disk as a JSON Lines file in the app's Caches directory, so the previous one
/// survives a relaunch or a crash. Everything it's given is already redacted, and every read and write
/// happens on its own background queue.
public final class SessionArchive: Sendable {
    /// What limits a session's file and the stores it's read back into.
    struct Limits: Sendable {
        var requests: Int
        var socketFrames: Int
        var socketPayloadBytes: Int

        /// The most a session's file may grow to before its oldest lines are dropped.
        var fileBytes = 50 * 1024 * 1024
    }

    static let formatVersion = 1

    /// Where sessions go unless a test says otherwise.
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Cerebro/Sessions", isDirectory: true)
    }

    private let writer: SessionFileWriter
    private let limits: Limits

    /// Nothing touches the disk here. The first thing the queue does is drop sessions past
    /// `previousSessionLimit` and start this launch's file.
    ///
    /// `onWrite` runs after each line is written, on the thread that wrote it, for tests.
    init(
        directory: URL,
        previousSessionLimit: Int,
        limits: Limits,
        startDate: Date = Date(),
        onWrite: (@Sendable () -> Void)? = nil
    ) {
        self.limits = limits
        writer = SessionFileWriter(
            directory: directory,
            previousSessionLimit: max(previousSessionLimit, 0),
            limits: limits,
            startDate: startDate,
            onWrite: onWrite
        )
    }

    /// Removes every saved session, for when persistence is turned off.
    static func removeAll(in directory: URL) {
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// The sessions earlier launches saved, newest first.
    public func previousSessions() async -> [StoredSessionReference] {
        await writer.previousSessions()
    }

    func append(_ record: SessionRecord) {
        writer.append(record)
    }

    /// Waits until everything appended so far is on disk.
    func flush() async {
        _ = await writer.previousSessions()
    }

    /// Reads a saved session. A line that doesn't decode, such as one cut short by a crash, is skipped.
    public func load(_ reference: StoredSessionReference) async -> StoredSession {
        let store = TransactionStore(requestLimit: limits.requests)
        let socketStore = SocketStore(frameLimit: limits.socketFrames, payloadByteLimit: limits.socketPayloadBytes)
        let records = await Task.detached(priority: .userInitiated) { Self.records(in: reference.id) }.value
        for record in records {
            switch record {
            case .header: break
            case .http(let transaction): await store.append(transaction)
            case .httpCleared: await store.removeAll()
            case .socket(let identity, let item): await socketStore.record(item, on: identity)
            }
        }
        return StoredSession(reference: reference, store: store, socketStore: socketStore)
    }

    private static func records(in file: URL) -> [SessionRecord] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: SessionFileWriter.newline).compactMap {
            try? decoder.decode(SessionRecord.self, from: $0)
        }
    }
}

/// Appends records to this launch's file, one line each as they arrive, so a crash loses at most what
/// was still in flight.
///
/// Safety for `@unchecked Sendable`: every mutable property is only touched on `queue`, which is serial.
final class SessionFileWriter: @unchecked Sendable {
    static let newline = UInt8(ascii: "\n")
    private static let filePrefix = "session-"
    private static let fileExtension = "jsonl"
    private static let httpLinePrefix = Data(#"{"http""#.utf8)
    private static let headerLinePrefix = Data(#"{"header""#.utf8)

    private let queue = DispatchQueue(label: "io.github.0xsiddhant.cerebro.sessions", qos: .utility)
    private let directory: URL
    private let limits: SessionArchive.Limits
    private let startDate: Date
    private let onWrite: (@Sendable () -> Void)?
    private let encoder = JSONEncoder()
    private var previous: [StoredSessionReference] = []
    private var file: URL?
    private var handle: FileHandle?
    private var fileBytes = 0
    private var httpLines = 0

    init(
        directory: URL,
        previousSessionLimit: Int,
        limits: SessionArchive.Limits,
        startDate: Date,
        onWrite: (@Sendable () -> Void)?
    ) {
        self.directory = directory
        self.limits = limits
        self.startDate = startDate
        self.onWrite = onWrite
        queue.async { [self] in prepare(keeping: previousSessionLimit) }
    }

    func append(_ record: SessionRecord) {
        queue.async { [self] in write(record) }
    }

    /// Runs after everything queued before it, so it also tells a caller when those writes are done.
    func previousSessions() async -> [StoredSessionReference] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: previous) }
        }
    }

    /// Keeps the newest sessions, deletes the rest, and starts this launch's file.
    private func prepare(keeping limit: Int) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .compactMap(Self.reference)
            .sorted { $0.startDate > $1.startDate }
        previous = Array(saved.prefix(limit))
        for old in saved.dropFirst(limit) {
            try? manager.removeItem(at: old.id)
        }
        let milliseconds = Int64((startDate.timeIntervalSince1970 * 1000).rounded())
        let name = "\(Self.filePrefix)\(milliseconds)-\(UUID().uuidString.prefix(8)).\(Self.fileExtension)"
        let file = directory.appendingPathComponent(name)
        guard manager.createFile(atPath: file.path, contents: nil) else { return }
        self.file = file
        handle = try? FileHandle(forWritingTo: file)
        write(.header(version: SessionArchive.formatVersion, startDate: startDate))
    }

    /// A session's start time is in its file name, so listing sessions never has to open one.
    private static func reference(for file: URL) -> StoredSessionReference? {
        let name = file.deletingPathExtension().lastPathComponent
        guard file.pathExtension == fileExtension, name.hasPrefix(filePrefix),
            let milliseconds = name.dropFirst(filePrefix.count).split(separator: "-").first.flatMap({ Double($0) })
        else { return nil }
        return StoredSessionReference(id: file, startDate: Date(timeIntervalSince1970: milliseconds / 1000))
    }

    private func write(_ record: SessionRecord) {
        guard let handle, var line = try? encoder.encode(record) else { return }
        line.append(Self.newline)
        guard (try? handle.write(contentsOf: line)) != nil else { return }
        fileBytes += line.count
        onWrite?()
        if case .http = record {
            httpLines += 1
        }
        if fileBytes > limits.fileBytes || httpLines > limits.requests * 2 {
            compact()
        }
    }

    /// Drops the oldest lines, keeping as many requests as the in-memory store does and half the byte
    /// limit, so this doesn't run again on the very next write. What's kept is the end of the file, so it's
    /// copied as one piece and never decoded.
    private func compact() {
        guard let file, let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return }
        var keptFrom = data.endIndex
        var keptRequests = 0
        var lineEnd = data.endIndex
        while lineEnd > data.startIndex {
            let body = data[data.startIndex..<(lineEnd - 1)]
            let lineStart = body.lastIndex(of: Self.newline).map { $0 + 1 } ?? data.startIndex
            let line = data[lineStart..<lineEnd]
            let isRequest = line.starts(with: Self.httpLinePrefix)
            guard !line.starts(with: Self.headerLinePrefix),
                data.endIndex - lineStart <= limits.fileBytes / 2,
                !(isRequest && keptRequests == limits.requests)
            else { break }
            keptRequests += isRequest ? 1 : 0
            keptFrom = lineStart
            lineEnd = lineStart
        }
        guard
            var contents = try? encoder.encode(
                SessionRecord.header(version: SessionArchive.formatVersion, startDate: startDate))
        else { return }
        contents.append(Self.newline)
        contents.append(data[keptFrom...])
        try? handle?.close()
        // Atomic, so a crash here leaves either the old file or the new one, never half of each.
        guard (try? contents.write(to: file, options: .atomic)) != nil else {
            handle = try? FileHandle(forWritingTo: file)
            _ = try? handle?.seekToEnd()
            return
        }
        handle = try? FileHandle(forWritingTo: file)
        _ = try? handle?.seekToEnd()
        fileBytes = contents.count
        httpLines = keptRequests
    }
}
