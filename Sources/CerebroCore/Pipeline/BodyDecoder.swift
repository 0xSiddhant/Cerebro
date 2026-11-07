import Foundation

/// Turns a body Cerebro can't read into JSON it can. PLAN-03's proto decoder conforms to this.
public protocol BodyDecoder: Sendable {
    /// Returns the decoded body as JSON, or `nil` if this decoder doesn't apply.
    func decode(_ body: Data, context: BodyContext) -> Data?
}

/// Where a body came from, so a decoder can tell whether it applies.
public struct BodyContext: Sendable, Equatable {
    /// Which way a body travelled.
    public enum Direction: Sendable, Equatable {
        /// From the app to the server.
        case request

        /// From the server to the app.
        case response
    }

    /// The request's URL.
    public let url: URL?

    /// The HTTP method.
    public let method: String

    /// The body's content type.
    public let contentType: String?

    /// Which way the body travelled.
    public let direction: Direction

    /// Creates a context.
    public init(url: URL?, method: String, contentType: String?, direction: Direction) {
        self.url = url
        self.method = method
        self.contentType = contentType
        self.direction = direction
    }
}
