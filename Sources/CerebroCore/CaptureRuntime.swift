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

    private let engine: HTTPCaptureEngine
    private let exchanges: AsyncStream<RawExchange>.Continuation
    private let processing: Task<Void, Never>
    private let socketEngine: SocketCaptureEngine
    private let socketActivity: AsyncStream<RawSocketActivity>.Continuation
    private let socketProcessing: Task<Void, Never>

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
        let processor = BodyProcessor(
            limit: bodyLimit,
            decoders: configuration.decoders,
            redactor: redactor
        )
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
        engine = HTTPCaptureEngine(bodyLimit: bodyLimit) { continuation.yield($0) }

        let (scaled, overflowed) = bodyLimit.multipliedReportingOverflow(by: Self.socketPayloadBodies)
        let payloadByteLimit = overflowed ? Int.max : scaled
        let socketStore = SocketStore(
            frameLimit: configuration.socketFrameLimit,
            payloadByteLimit: payloadByteLimit
        )
        let socketBuilder = SocketActivityBuilder(processor: processor)
        let backlog = SocketBacklog(frameLimit: Self.socketBacklogFrames, byteLimit: payloadByteLimit)
        // Unbounded because `backlog` limits the payloads. Dropping from here could lose a close.
        let (activities, activityInput) = AsyncStream.makeStream(
            of: RawSocketActivity.self,
            bufferingPolicy: .unbounded
        )
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
    }
}
