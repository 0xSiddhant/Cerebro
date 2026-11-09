/// How much Cerebro prints to the console for each request.
public enum ConsoleLevel: Sendable {
    /// Prints nothing.
    case off

    /// Prints one line per request.
    case summary

    /// Prints headers and decoded bodies too.
    case full
}
