import Foundation

/// A running capture: the engine, the pipeline behind it, and the store they fill.
public final class CaptureRuntime: Sendable {
    /// How much payload all sockets may hold together, as a multiple of the stored-body cap.
    private static let socketPayloadBodies = 100

    /// How many frames can wait for the pipeline, across every socket.
    private static let socketBacklogFrames = 10_000

    /// Where finished transactions land.
    public let store: TransactionStore

    /// Where socket activity lands.
    public let socketStore: SocketStore

    /// The network the device is on.
    public let systemInfo: SystemInfoMonitor

    /// The foreground downloads still running.
    public let downloads: DownloadProgressStore

    private let engine: HTTPCaptureEngine
    private let exchanges: AsyncStream<RawExchange>.Continuation
    private let processing: Task<Void, Never>
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

    init(unchecked configuration: CerebroConfiguration, console: ConsoleLogger? = nil) {
        let store = TransactionStore(requestLimit: configuration.requestLimit)
        let redactor = Redactor(rules: configuration.redaction)
        // A limit below zero means store nothing, and must never reach code that assumes a size.
        let bodyLimit = max(configuration.bodyLimit, 0)
        let processor = BodyProcessor(limit: bodyLimit, decoders: configuration.decoders, redactor: redactor)
        let builder = TransactionBuilder(processor: processor, redactor: redactor)
        let console = console ?? ConsoleLogger(level: configuration.consoleLevel)
        let (stream, continuation) = AsyncStream.makeStream(
            of: RawExchange.self,
            bufferingPolicy: .bufferingNewest(configuration.requestLimit)
        )
        self.store = store
        exchanges = continuation
        // One detached task, so transactions stay in order and never run on the main thread.
        processing = Task.detached(priority: .utility) {
            for await exchange in stream {
                let transaction = builder.transaction(from: exchange)
                await store.append(transaction)
                console.log(transaction)
            }
        }
        let downloads = DownloadProgressStore()
        let eventInput = Self.trackDownloads(in: downloads, redactor: redactor)
        self.downloads = downloads
        downloadEvents = eventInput
        engine = HTTPCaptureEngine(
            bodyLimit: bodyLimit,
            reportDownload: { eventInput.yield($0) },
            record: { continuation.yield($0) }
        )
        systemInfo = SystemInfoMonitor(lookup: .ifEnabled(configuration.isPublicIPLookupEnabled))

        let payloadByteLimit = Self.socketPayloadByteLimit(forBodyLimit: bodyLimit)
        let socketStore = SocketStore(frameLimit: configuration.socketFrameLimit, payloadByteLimit: payloadByteLimit)
        let socketBuilder = SocketActivityBuilder(processor: processor)
        let backlog = SocketBacklog(frameLimit: Self.socketBacklogFrames, byteLimit: payloadByteLimit)
        // Unbounded because `backlog` limits the payloads. Dropping from here could lose a close.
        let (activities, activityInput) = AsyncStream.makeStream(
            of: RawSocketActivity.self, bufferingPolicy: .unbounded)
        self.socketStore = socketStore
        socketActivity = activityInput
        // One detached task, so frames stay in order and never run on the main thread.
        socketProcessing = Task.detached(priority: .utility) {
            for await activity in activities {
                await socketStore.record(socketBuilder.item(from: activity), on: activity.socket)
                backlog.finish(bytes: activity.backlogBytes)
            }
        }
        socketEngine = SocketCaptureEngine(bodyLimit: bodyLimit, backlog: backlog, redactor: redactor) {
            activityInput.yield($0)
        }
    }

    private static func socketPayloadByteLimit(forBodyLimit bodyLimit: Int) -> Int {
        let (scaled, overflowed) = bodyLimit.multipliedReportingOverflow(by: socketPayloadBodies)
        return overflowed ? Int.max : scaled
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
        socketEngine.uninstall()
        socketActivity.finish()
        downloadEvents.finish()
        Task { [systemInfo] in await systemInfo.stop() }
    }
}
