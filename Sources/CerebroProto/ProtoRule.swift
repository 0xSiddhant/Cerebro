import SwiftProtobuf

#if SWIFT_PACKAGE
import CerebroCore
#elseif CEREBRO_PROTO_STANDALONE
import Cerebro
#endif

/// Ties traffic to a protobuf message type. Plan 3 adds the matcher, direction and framing.
public struct ProtoRule: Sendable {
    public let messageType: any SwiftProtobuf.Message.Type

    public init(messageType: any SwiftProtobuf.Message.Type) {
        self.messageType = messageType
    }
}

extension CerebroConfiguration {
    /// Keeps this module's dependency on the core under test until Plan 3 registers real rules.
    public func registering(_ rules: [ProtoRule]) -> CerebroConfiguration {
        self
    }
}
