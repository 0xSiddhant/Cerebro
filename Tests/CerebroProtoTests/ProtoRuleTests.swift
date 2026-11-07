import SwiftProtobuf
import Testing
@testable import CerebroProto

@Test func ruleKeepsItsMessageType() {
    let rule = ProtoRule(messageType: Google_Protobuf_Struct.self)
    #expect(rule.messageType == Google_Protobuf_Struct.self)
}
