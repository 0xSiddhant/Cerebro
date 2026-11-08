/// What `Cerebro.start` takes. Every setting has a working default.
public struct CerebroConfiguration: Sendable {
    /// Whether capture runs in distribution-signed builds, such as QA and TestFlight builds.
    public var allowsDistributionBuilds: Bool

    /// How much each request prints to the console.
    public var consoleLevel: ConsoleLevel

    /// How many requests are kept. The oldest is dropped first.
    public var requestLimit: Int

    /// The most bytes stored for each request or response body.
    public var bodyLimit: Int

    /// How many frames and events are kept for each socket. The oldest is dropped first.
    public var socketFrameLimit: Int

    /// What to redact on top of the default headers.
    public var redaction: RedactionRules

    /// Whether shaking the device shows or hides the floating trigger.
    public var isShakeGestureEnabled: Bool

    /// Decoders tried in order on each body. PLAN-03 registers the proto decoder here.
    public var decoders: [any BodyDecoder]

    /// Creates a configuration. Every argument has a working default.
    public init(
        allowsDistributionBuilds: Bool = false,
        consoleLevel: ConsoleLevel = .summary,
        requestLimit: Int = 500,
        bodyLimit: Int = 1_048_576,
        socketFrameLimit: Int = 1_000,
        redaction: RedactionRules = RedactionRules(),
        isShakeGestureEnabled: Bool = true,
        decoders: [any BodyDecoder] = []
    ) {
        self.allowsDistributionBuilds = allowsDistributionBuilds
        self.consoleLevel = consoleLevel
        self.requestLimit = requestLimit
        self.bodyLimit = bodyLimit
        self.socketFrameLimit = socketFrameLimit
        self.redaction = redaction
        self.isShakeGestureEnabled = isShakeGestureEnabled
        self.decoders = decoders
    }
}
