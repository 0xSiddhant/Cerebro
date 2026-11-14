import Foundation
import SwiftProtobuf
import os

#if SWIFT_PACKAGE
import CerebroCore
#elseif CEREBRO_PROTO_STANDALONE
import Cerebro
#endif

/// Turns protobuf into JSON using the app's rules. Runs on the background pipeline.
struct ProtoDecoder: BodyDecoder {
    private static let grpcHeaderLength = 5

    /// Code rules first, then file rules, each in the order they were given.
    let rules: [ProtoRule]

    private let matchCounts: OSAllocatedUnfairLock<[Int]>

    init(rules: [ProtoRule]) {
        self.rules = rules.filter { $0.source == .code } + rules.filter { $0.source != .code }
        matchCounts = OSAllocatedUnfairLock(initialState: Array(repeating: 0, count: rules.count))
    }

    func decode(_ body: Data, context: BodyContext) -> Data? {
        guard let index = countMatch(for: context) else { return nil }
        return Self.json(from: body, rule: rules[index], context: context)
    }

    func noteSkippedBody(context: BodyContext) {
        _ = countMatch(for: context)
    }

    private func countMatch(for context: BodyContext) -> Int? {
        guard let index = rules.firstIndex(where: { $0.applies(to: context) }) else { return nil }
        matchCounts.withLock { $0[index] += 1 }
        return index
    }

    func claims(_ context: BodyContext) -> Bool {
        rules.contains { $0.applies(to: context) }
    }

    var mappings: [DecoderMapping] {
        let counts = matchCounts.withLock { $0 }
        return zip(rules, counts).map { rule, count in
            DecoderMapping(
                name: rule.name,
                matcher: rule.matcherSummary,
                direction: rule.direction.summary,
                messageType: rule.messageType.protoMessageName,
                source: rule.source,
                matchCount: count
            )
        }
    }

    private static func json(from body: Data, rule: ProtoRule, context: BodyContext) -> Data? {
        guard let payload = payload(of: body, rule: rule, context: context),
            let message = try? rule.messageType.init(serializedBytes: payload, partial: true)
        else { return nil }
        // Proto field names, so the keys match the `.proto` file and redaction rules written from it.
        var options = JSONEncodingOptions()
        options.preserveProtoFieldNames = true
        guard let json = try? message.jsonString(options: options) else { return nil }
        // Bytes that are all unknown fields aren't this message, and `{}` would say they decoded.
        return json == "{}" && !payload.isEmpty ? nil : Data(json.utf8)
    }

    private static func payload(of body: Data, rule: ProtoRule, context: BodyContext) -> Data? {
        guard body.count >= rule.stripPrefixBytes else { return nil }
        let message = Data(body.dropFirst(rule.stripPrefixBytes))
        guard rule.stripPrefixBytes == grpcHeaderLength,
            context.contentType?.lowercased().hasPrefix("application/grpc") == true
        else { return message }
        // gRPC's header ends with the message's length, and a frame of trailers can follow the message.
        let length = body.prefix(grpcHeaderLength).dropFirst().reduce(0) { ($0 << 8) | Int($1) }
        return length <= message.count ? Data(message.prefix(length)) : message
    }
}
