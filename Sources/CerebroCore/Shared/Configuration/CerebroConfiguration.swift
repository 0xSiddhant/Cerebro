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

    /// What to redact. Nothing is redacted until it's selected here.
    public var redaction: RedactionRules

    /// Whether shaking the device shows or hides the floating trigger.
    public var isShakeGestureEnabled: Bool

    /// Decoders tried in order on each body. `registering(_:)` adds the proto decoder here.
    public var decoders: [any BodyDecoder]

    /// Whether the System Info tab asks `api.ipify.org` for the device's public IP. Off by default,
    /// because it's the only data Cerebro sends off the device.
    public var isPublicIPLookupEnabled: Bool

    /// Whether each session is also kept on disk, in the app's Caches directory and already redacted, so
    /// the previous one can be read after a relaunch or a crash. Turning it off removes what was saved.
    public var isPersistenceEnabled: Bool

    /// How many earlier sessions stay on disk. Older ones are removed at each launch.
    public var previousSessionLimit: Int

    /// Creates a configuration. Every argument has a working default.
    public init(
        allowsDistributionBuilds: Bool = false,
        consoleLevel: ConsoleLevel = .summary,
        requestLimit: Int = 500,
        bodyLimit: Int = 1_048_576,
        socketFrameLimit: Int = 1_000,
        redaction: RedactionRules = RedactionRules(),
        isShakeGestureEnabled: Bool = true,
        decoders: [any BodyDecoder] = [],
        isPublicIPLookupEnabled: Bool = false,
        isPersistenceEnabled: Bool = true,
        previousSessionLimit: Int = 1
    ) {
        self.allowsDistributionBuilds = allowsDistributionBuilds
        self.consoleLevel = consoleLevel
        self.requestLimit = requestLimit
        self.bodyLimit = bodyLimit
        self.socketFrameLimit = socketFrameLimit
        self.redaction = redaction
        self.isShakeGestureEnabled = isShakeGestureEnabled
        self.decoders = decoders
        self.isPublicIPLookupEnabled = isPublicIPLookupEnabled
        self.isPersistenceEnabled = isPersistenceEnabled
        self.previousSessionLimit = previousSessionLimit
    }
}
