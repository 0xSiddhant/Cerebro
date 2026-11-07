import Foundation

/// A running capture: the engine, the pipeline behind it, and the store they fill.
public final class CaptureRuntime: Sendable {
    /// Where finished transactions land.
    public let store: TransactionStore

    private let engine: HTTPCaptureEngine
    private let exchanges: AsyncStream<RawExchange>.Continuation
    private let processing: Task<Void, Never>

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
        let builder = TransactionBuilder(
            processor: BodyProcessor(
                limit: configuration.bodyLimit,
                decoders: configuration.decoders,
                redactor: redactor
            ),
            redactor: redactor
        )
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
        engine = HTTPCaptureEngine(bodyLimit: configuration.bodyLimit) { continuation.yield($0) }
    }

    /// Starts capturing.
    public func start() {
        engine.install()
    }

    /// Stops capturing. Anything already captured still reaches the store.
    public func stop() {
        engine.uninstall()
        exchanges.finish()
    }
}
