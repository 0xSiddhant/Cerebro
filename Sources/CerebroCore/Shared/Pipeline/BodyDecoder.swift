import Foundation

/// Turns a body Cerebro can't read into JSON it can. `CerebroProto`'s decoder conforms to this.
public protocol BodyDecoder: Sendable {
    /// Returns the decoded body as JSON, or `nil` if this decoder doesn't apply.
    func decode(_ body: Data, context: BodyContext) -> Data?

    /// Whether this decoder is responsible for bodies like this one, even when it can't decode them.
    func claims(_ context: BodyContext) -> Bool

    /// Tells this decoder about a body it claims that was too large to try.
    func noteSkippedBody(context: BodyContext)

    /// What this decoder applies to, for the dashboard to list.
    var mappings: [DecoderMapping] { get }
}

extension BodyDecoder {
    /// Claims nothing, for decoders that only ever try `decode`.
    public func claims(_ context: BodyContext) -> Bool {
        false
    }

    /// Ignores the body, for decoders that keep no count.
    public func noteSkippedBody(context: BodyContext) {}

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
    private static let base64ProtobufContentType = "application/grpc-web-text"
    private static let textSubtypes = ["json", "xml", "html", "form-urlencoded", base64ProtobufContentType]

    /// The content type without its parameters, so a parameter's value can't be mistaken for the type.
    private var mediaType: String? {
        contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Whether the content type says this body is text, which no binary decoder can read.
    public var declaresText: Bool {
        guard let mediaType else { return false }
        return mediaType.hasPrefix("text/") || Self.textSubtypes.contains { mediaType.contains($0) }
    }

    /// Whether the content type says this body is binary protobuf, with or without a rule for it.
    var isProtobuf: Bool {
        guard let mediaType, !declaresText else { return false }
        return Self.protobufContentTypes.contains { mediaType.hasPrefix($0) }
    }

    /// Whether this is gRPC-web's base64 form, which hides field names from a search of its text.
    var isBase64Protobuf: Bool {
        mediaType?.hasPrefix(Self.base64ProtobufContentType) == true
    }
}
