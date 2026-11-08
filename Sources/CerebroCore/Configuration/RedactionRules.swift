/// What to redact on top of the default headers. Names are matched without regard to case.
public struct RedactionRules: Sendable {
    /// Extra header names to redact.
    public var headers: Set<String>

    /// Body field names to redact: JSON keys at any depth, and form-encoded fields. Setting these makes
    /// Cerebro parse those bodies at capture. Any other text can't be redacted field by field, so it's
    /// withheld if it names a key. Binary bodies are stored as sent.
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
