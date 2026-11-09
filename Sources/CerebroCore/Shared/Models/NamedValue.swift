/// One name and value, from a header or a query string.
public struct NamedValue: Sendable, Equatable {
    /// The name.
    public let name: String

    /// The value, already redacted if a rule matched.
    public let value: String

    /// Creates a pair.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
