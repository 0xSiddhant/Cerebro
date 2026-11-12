import Foundation

/// A running capture: the engine, the pipeline behind it, and the store they fill.
public final class CaptureRuntime: Sendable {
    /// How much payload all sockets may hold together, as a multiple of the stored-body cap.
    private static let socketPayloadBodies = 100

    /// How many frames can wait for the pipeline, across every socket.
    private static let socketBacklogFrames = 10_000

    /// The least time between two updates of one open event stream, so a fast one can't flood the store.
    private static let eventStreamUpdateInterval = Duration.milliseconds(250)

    /// Where finished transactions land.
    public let store: TransactionStore

    /// Where socket activity lands.
    public let socketStore: SocketStore

    /// The network the device is on.
    public let systemInfo: SystemInfoMonitor

    /// The foreground downloads still running.
    public let downloads: DownloadProgressStore

    /// The sessions kept on disk, or `nil` if persistence is off.
    public let archive: SessionArchive?

    private let engine: HTTPCaptureEngine
    private let exchanges: AsyncStream<RawExchange>.Continuation
    private let processing: Task<Void, Never>
    private let eventStreams: AsyncStream<RawStreamActivity>.Continuation
    private let socketEngine: SocketCaptureEngine
    private let socketActivity: AsyncStream<RawSocketActivity>.Continuation
    private let socketProcessing: Task<Void, Never>
    private let downloadEvents: AsyncStream<DownloadEvent>.Continuation

    /// Creates a runtime, or returns `nil` if this build must not run Cerebro.
    public convenience init?(configuration: CerebroConfiguration) {
        self.init(configuration: configuration, environment: .current)
    }

    convenience init?(configuration: CerebroConfiguration, environment: ReleaseGate.Environment) {
        guard
            ReleaseGate.isOpen(
                allowsDistributionBuilds: configuration.allowsDistributionBuilds, environment: environment)
        else { return nil }
        self.init(unchecked: configuration)
    }

    /// `sessionsDirectory` is where sessions are kept. `nil` keeps nothing and removes nothing.
    init(
        unchecked configuration: CerebroConfiguration,
        console: ConsoleLogger? = nil,
        sessionsDirectory: URL? = SessionArchive.defaultDirectory
    ) {
        let redactor = Redactor(rules: configuration.redaction)
        // A limit below zero means store nothing, and must never reach code that assumes a size.
        let bodyLimit = max(configuration.bodyLimit, 0)
        let payloadByteLimit = Self.socketPayloadByteLimit(forBodyLimit: bodyLimit)
        let archive = Self.makeArchive(configuration, in: sessionsDirectory, socketPayloadBytes: payloadByteLimit)
        self.archive = archive
        // Everything the stores hold is already redacted, so that's all that can reach the disk.
        let journal = archive.map { archive in { @Sendable record in archive.append(record) } }
        let store = TransactionStore(requestLimit: configuration.requestLimit, journal: journal)
        let processor = BodyProcessor(limit: bodyLimit, decoders: configuration.decoders, redactor: redactor)
        let builder = TransactionBuilder(processor: processor, redactor: redactor)
        let console = console ?? ConsoleLogger(level: configuration.consoleLevel)
        let (stream, continuation) = AsyncStream.makeStream(
            of: RawExchange.self,
            bufferingPolicy: .bufferingNewest(configuration.requestLimit)
        )
        self.store = store
        exchanges = continuation
        processing = Self.process(stream, builder: builder, store: store, console: console)
        let streamInput = Self.processEventStreams(builder: builder, store: store, console: console)
        eventStreams = streamInput
        let downloads = DownloadProgressStore()
        let eventInput = Self.trackDownloads(in: downloads, redactor: redactor)
        self.downloads = downloads
        downloadEvents = eventInput
        engine = HTTPCaptureEngine(
            bodyLimit: bodyLimit,
            reportDownload: { eventInput.yield($0) },
            recordStream: { streamInput.yield($0) },
            record: { continuation.yield($0) }
        )
        systemInfo = SystemInfoMonitor(lookup: .ifEnabled(configuration.isPublicIPLookupEnabled))

        let socketStore = SocketStore(frameLimit: configuration.socketFrameLimit, payloadByteLimit: payloadByteLimit)
        let socketBuilder = SocketActivityBuilder(processor: processor)
        let backlog = CaptureBacklog(frameLimit: Self.socketBacklogFrames, byteLimit: payloadByteLimit)
        // Unbounded because `backlog` limits the payloads. Dropping from here could lose a close.
        let (activities, activityInput) = AsyncStream.makeStream(
            of: RawSocketActivity.self, bufferingPolicy: .unbounded)
        self.socketStore = socketStore
        socketActivity = activityInput
        // One detached task, so frames stay in order and never run on the main thread.
        socketProcessing = Task.detached(priority: .utility) {
            await socketStore.setJournal(journal)
            for await activity in activities {
                await socketStore.record(socketBuilder.item(from: activity), on: activity.socket)
                backlog.finish(bytes: activity.backlogBytes)
            }
        }
        socketEngine = SocketCaptureEngine(bodyLimit: bodyLimit, backlog: backlog, redactor: redactor) {
            activityInput.yield($0)
        }
    }

    /// With persistence off, what earlier launches saved is removed too, so nothing stays on disk.
    private static func makeArchive(
        _ configuration: CerebroConfiguration,
        in directory: URL?,
        socketPayloadBytes: Int
    ) -> SessionArchive? {
        guard let directory else { return nil }
        guard configuration.isPersistenceEnabled else {
            SessionArchive.removeAll(in: directory)
            return nil
        }
        return SessionArchive(
            directory: directory,
            previousSessionLimit: configuration.previousSessionLimit,
            limits: SessionArchive.Limits(
                requests: configuration.requestLimit,
                socketFrames: configuration.socketFrameLimit,
                socketPayloadBytes: socketPayloadBytes
            )
        )
    }

    private static func socketPayloadByteLimit(forBodyLimit bodyLimit: Int) -> Int {
        let (scaled, overflowed) = bodyLimit.multipliedReportingOverflow(by: socketPayloadBodies)
        return overflowed ? Int.max : scaled
    }

    /// One detached task, so transactions stay in order and never run on the main thread.
    private static func process(
        _ exchanges: AsyncStream<RawExchange>,
        builder: TransactionBuilder,
        store: TransactionStore,
        console: ConsoleLogger
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            for await exchange in exchanges {
                let transaction = builder.transaction(from: exchange)
                await store.append(transaction)
                console.log(transaction)
            }
        }
    }

    /// Feeds event streams to the store through one ordered queue. It's unbounded because each stream's
    /// own backlog limits its bytes, and dropping from here could lose a stream's end and leave it open.
    private static func processEventStreams(
        builder: TransactionBuilder,
        store: TransactionStore,
        console: ConsoleLogger
    ) -> AsyncStream<RawStreamActivity>.Continuation {
        let (activities, input) = AsyncStream.makeStream(of: RawStreamActivity.self, bufferingPolicy: .unbounded)
        // One detached task, so each stream's events stay in order and never run on the main thread.
        Task.detached(priority: .utility) {
            var processor = EventStreamProcessor(builder: builder, store: store, console: console) { id in
                Task.detached(priority: .utility) {
                    try? await Task.sleep(for: eventStreamUpdateInterval)
                    input.yield(RawStreamActivity(id: id, content: .flush, date: Date()))
                }
            }
            for await activity in activities {
                await processor.handle(activity)
            }
        }
        return input
    }

    /// Feeds download progress to its store through one ordered stream, so a download's end can't
    /// overtake its last progress report.
    private static func trackDownloads(
        in downloads: DownloadProgressStore,
        redactor: Redactor
    ) -> AsyncStream<DownloadEvent>.Continuation {
        let (events, input) = AsyncStream.makeStream(of: DownloadEvent.self, bufferingPolicy: .unbounded)
        Task.detached(priority: .utility) {
            for await event in events {
                // The URL is redacted here, before anything outside the pipeline can read it.
                if case .started(let id, let url, let date) = event {
                    await downloads.apply(.started(id: id, url: redactor.redact(url: url), date: date))
                } else {
                    await downloads.apply(event)
                }
            }
            // Capture stopped, so a download still running can never report that it finished.
            await downloads.removeAll()
        }
        return input
    }

    /// Starts capturing.
    public func start() {
        engine.install()
        socketEngine.install()
    }

    /// Stops capturing. Anything already captured still reaches the store.
    public func stop() {
        engine.uninstall()
        exchanges.finish()
        eventStreams.finish()
        socketEngine.uninstall()
        socketActivity.finish()
        downloadEvents.finish()
        Task { [systemInfo] in await systemInfo.stop() }
    }
}
