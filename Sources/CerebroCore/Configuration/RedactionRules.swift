/// What to redact on top of the default headers. Names are matched without regard to case.
public struct RedactionRules: Sendable {
    /// Extra header names to redact.
    public var headers: Set<String>

    /// JSON keys to redact, at any depth. Setting these makes Cerebro parse JSON bodies at capture.
    public var jsonKeys: Set<String>

    /// Query parameters to redact.
    public var queryParameters: Set<String>

    /// Creates a set of rules. Every argument defaults to nothing extra.
    public init(headers: Set<String> = [], jsonKeys: Set<String> = [], queryParameters: Set<String> = []) {
        self.headers = headers
        self.jsonKeys = jsonKeys
        self.queryParameters = queryParameters
    }
}
