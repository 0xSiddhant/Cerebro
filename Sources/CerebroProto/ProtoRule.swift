import Foundation
import SwiftProtobuf

#if SWIFT_PACKAGE
import CerebroCore
#elseif CEREBRO_PROTO_STANDALONE
import Cerebro
#endif

/// Ties traffic to a protobuf message type, so the dashboard can show it as JSON.
public struct ProtoRule: Sendable {
    /// Which traffic a rule applies to. Every part that's set has to match, and a part left out matches
    /// anything.
    public struct Match: Sendable {
        /// The URL's host, ignoring case.
        public let host: String?

        /// The URL's exact path.
        public let path: String?

        /// The start of the URL's path.
        public let pathPrefix: String?

        /// A regular expression that must be found in the URL's path. An invalid one never matches.
        public let regex: String?

        private let expression: NSRegularExpression?

        /// Creates a match.
        public init(host: String? = nil, path: String? = nil, pathPrefix: String? = nil, regex: String? = nil) {
            self.host = host
            self.path = path
            self.pathPrefix = pathPrefix
            self.regex = regex
            expression = regex.flatMap { try? NSRegularExpression(pattern: $0) }
        }

        func matches(_ url: URL?) -> Bool {
            if let host, url?.host?.caseInsensitiveCompare(host) != .orderedSame {
                return false
            }
            let urlPath = url?.path ?? ""
            if let path, urlPath != path {
                return false
            }
            if let pathPrefix, !urlPath.hasPrefix(pathPrefix) {
                return false
            }
            guard regex != nil else { return true }
            let range = NSRange(urlPath.startIndex..., in: urlPath)
            return expression?.firstMatch(in: urlPath, range: range) != nil
        }

        var summary: String {
            let parts = [host, path, pathPrefix.map { $0 + "*" }, regex.map { "regex \($0)" }].compactMap { $0 }
            return parts.isEmpty ? "Any URL" : parts.joined(separator: " ")
        }
    }

    /// Which way the traffic a rule decodes is going.
    public enum Direction: Sendable, Equatable {
        /// The body of an HTTP request.
        case request

        /// The body of an HTTP response.
        case response

        /// A binary socket frame the app sends.
        case socketOutgoing

        /// A binary socket frame the app receives.
        case socketIncoming

        func fits(_ context: BodyContext) -> Bool {
            switch self {
            case .request: return context.carrier == .http && context.direction == .request
            case .response: return context.carrier == .http && context.direction == .response
            case .socketOutgoing: return context.carrier == .binaryFrame && context.direction == .request
            case .socketIncoming: return context.carrier == .binaryFrame && context.direction == .response
            }
        }

        var summary: String {
            switch self {
            case .request: return "Request"
            case .response: return "Response"
            case .socketOutgoing: return "Socket, outgoing"
            case .socketIncoming: return "Socket, incoming"
            }
        }
    }

    /// The label the Proto Config tab shows.
    public let name: String?

    /// Which traffic this rule applies to.
    public let match: Match

    /// The HTTP methods this rule applies to. Empty means any method.
    public let methods: Set<String>

    /// Which way the traffic is going.
    public let direction: Direction

    /// The message type that decodes matching traffic.
    public let messageType: any SwiftProtobuf.Message.Type

    /// How many bytes to drop before decoding, such as 5 for gRPC-web's header.
    public let stripPrefixBytes: Int

    /// Where this rule was defined.
    public let source: DecoderMapping.Source

    /// Creates a rule.
    public init(
        name: String? = nil,
        match: Match = Match(),
        methods: Set<String> = [],
        direction: Direction,
        messageType: any SwiftProtobuf.Message.Type,
        stripPrefixBytes: Int = 0,
        source: DecoderMapping.Source = .code
    ) {
        self.name = name
        self.match = match
        self.methods = Set(methods.map { $0.uppercased() })
        self.direction = direction
        self.messageType = messageType
        self.stripPrefixBytes = max(stripPrefixBytes, 0)
        self.source = source
    }

    func applies(to context: BodyContext) -> Bool {
        guard direction.fits(context), match.matches(context.url) else { return false }
        return context.carrier != .http || methods.isEmpty || methods.contains(context.method.uppercased())
    }

    var matcherSummary: String {
        methods.isEmpty ? match.summary : "\(methods.sorted().joined(separator: ", ")) \(match.summary)"
    }
}

extension CerebroConfiguration {
    /// Adds protobuf rules, usually your code rules together with `ProtoRule.generated`. Code rules are
    /// checked first, then file rules in file order, and the first match wins.
    public func registering(_ rules: [ProtoRule]) -> CerebroConfiguration {
        guard !rules.isEmpty else { return self }
        var configuration = self
        let registered = decoders.compactMap { $0 as? ProtoDecoder }.flatMap(\.rules)
        configuration.decoders.removeAll { $0 is ProtoDecoder }
        configuration.decoders.append(ProtoDecoder(rules: registered + rules))
        return configuration
    }
}
