import Foundation

/// Turns a body Cerebro can't read into JSON it can. `CerebroProto`'s decoder conforms to this.
public protocol BodyDecoder: Sendable {
    /// Returns the decoded body as JSON, or `nil` if this decoder doesn't apply.
    func decode(_ body: Data, context: BodyContext) -> Data?

    /// Whether this decoder is responsible for bodies like this one, even when it can't decode them.
    func claims(_ context: BodyContext) -> Bool

    /// What this decoder applies to, for the dashboard to list.
    var mappings: [DecoderMapping] { get }
}

extension BodyDecoder {
    /// Claims nothing, for decoders that only ever try `decode`.
    public func claims(_ context: BodyContext) -> Bool {
        false
    }

    /// Lists nothing, for decoders with no rules to show.
    public var mappings: [DecoderMapping] {
        []
    }
}

/// One rule a decoder applies, as the dashboard lists it.
public struct DecoderMapping: Sendable, Equatable {
    /// Where a rule was defined.
    public enum Source: Sendable, Equatable {
        /// In the app's code.
        case code

        /// In `traffic_map.json`.
        case file
    }

    /// The rule's label, if it has one.
    public let name: String?

    /// The traffic the rule matches, as text.
    public let matcher: String

    /// Which way the traffic goes, as text.
    public let direction: String

    /// The message type that decodes matching traffic.
    public let messageType: String

    /// Where the rule was defined.
    public let source: Source

    /// How many bodies have matched the rule so far.
    public let matchCount: Int

    /// Creates a mapping.
    public init(
        name: String?,
        matcher: String,
        direction: String,
        messageType: String,
        source: Source,
        matchCount: Int
    ) {
        self.name = name
        self.matcher = matcher
        self.direction = direction
        self.messageType = messageType
        self.source = source
        self.matchCount = matchCount
    }
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

    /// What carried a body.
    public enum Carrier: Sendable, Equatable {
        /// An HTTP request or response.
        case http

        /// A text socket frame.
        case textFrame

        /// A binary socket frame.
        case binaryFrame
    }

    /// The request's URL.
    public let url: URL?

    /// The HTTP method.
    public let method: String

    /// The body's content type.
    public let contentType: String?

    /// Which way the body travelled.
    public let direction: Direction

    /// What carried the body.
    public let carrier: Carrier

    /// Creates a context.
    public init(url: URL?, method: String, contentType: String?, direction: Direction, carrier: Carrier = .http) {
        self.url = url
        self.method = method
        self.contentType = contentType
        self.direction = direction
        self.carrier = carrier
    }
}

extension BodyContext {
    private static let protobufContentTypes = ["application/x-protobuf", "application/protobuf", "application/grpc"]

    /// Whether the content type says this body is protobuf, with or without a rule for it.
    var isProtobuf: Bool {
        guard let type = contentType?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return Self.protobufContentTypes.contains { type.hasPrefix($0) }
    }
}
