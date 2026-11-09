import Foundation
import SwiftProtobuf
import Testing
@testable import CerebroCore
@testable import CerebroProto

private func context(
    _ address: String = "https://api.example.com/v1/quotes/1",
    method: String = "GET",
    contentType: String? = nil,
    direction: BodyContext.Direction = .response,
    carrier: BodyContext.Carrier = .http
) -> BodyContext {
    BodyContext(
        url: URL(string: address),
        method: method,
        contentType: contentType,
        direction: direction,
        carrier: carrier
    )
}

private func rule(
    match: ProtoRule.Match = ProtoRule.Match(),
    methods: Set<String> = [],
    direction: ProtoRule.Direction = .response
) -> ProtoRule {
    ProtoRule(match: match, methods: methods, direction: direction, messageType: Google_Protobuf_Struct.self)
}

@Test func anEmptyMatchAppliesToAnyURL() {
    #expect(rule().applies(to: context()))
}

@Test func hostMatchesIgnoringCase() {
    #expect(rule(match: .init(host: "API.example.com")).applies(to: context()))
    #expect(!rule(match: .init(host: "other.example.com")).applies(to: context()))
}

@Test func pathMustMatchExactly() {
    #expect(rule(match: .init(path: "/v1/quotes/1")).applies(to: context()))
    #expect(!rule(match: .init(path: "/v1/quotes")).applies(to: context()))
}

@Test func pathPrefixMatchesTheStartOfThePath() {
    #expect(rule(match: .init(pathPrefix: "/v1/quotes")).applies(to: context()))
    #expect(!rule(match: .init(pathPrefix: "/quotes")).applies(to: context()))
}

@Test func regexIsFoundInThePath() {
    #expect(rule(match: .init(regex: "^/v1/quotes/[0-9]+$")).applies(to: context()))
    #expect(!rule(match: .init(regex: "^/v2/")).applies(to: context()))
}

@Test func anInvalidRegexNeverMatches() {
    #expect(!rule(match: .init(regex: "([")).applies(to: context()))
}

@Test func everyPartOfAMatchHasToHold() {
    #expect(rule(match: .init(host: "api.example.com", pathPrefix: "/v1")).applies(to: context()))
    #expect(!rule(match: .init(host: "api.example.com", pathPrefix: "/v2")).applies(to: context()))
}

@Test func methodsFilterIgnoringCase() {
    #expect(rule(methods: ["get"]).applies(to: context(method: "GET")))
    #expect(!rule(methods: ["POST"]).applies(to: context(method: "GET")))
}

@Test func directionSeparatesRequestsFromResponses() {
    #expect(rule(direction: .request).applies(to: context(direction: .request)))
    #expect(!rule(direction: .request).applies(to: context(direction: .response)))
}

@Test func socketRulesOnlyApplyToBinaryFramesGoingTheirWay() {
    let outgoing = context(direction: .request, carrier: .binaryFrame)
    let incoming = context(direction: .response, carrier: .binaryFrame)

    #expect(rule(direction: .socketOutgoing).applies(to: outgoing))
    #expect(!rule(direction: .socketOutgoing).applies(to: incoming))
    #expect(rule(direction: .socketIncoming).applies(to: incoming))
}

@Test func httpRulesIgnoreSocketFramesAndSocketRulesIgnoreHTTP() {
    #expect(!rule(direction: .response).applies(to: context(carrier: .binaryFrame)))
    #expect(!rule(direction: .socketIncoming).applies(to: context()))
}

@Test func textFramesAreNeverDecoded() {
    #expect(!rule(direction: .socketIncoming).applies(to: context(carrier: .textFrame)))
}

@Test func aMethodFilterDoesntAffectSocketFrames() {
    let frame = context(method: "SOCKET", carrier: .binaryFrame)

    #expect(rule(methods: ["GET"], direction: .socketIncoming).applies(to: frame))
}

@Test func aNegativePrefixIsTreatedAsZero() {
    let rule = ProtoRule(direction: .response, messageType: Google_Protobuf_Struct.self, stripPrefixBytes: -3)

    #expect(rule.stripPrefixBytes == 0)
}

@Test func noRulesAddNoDecoder() {
    #expect(CerebroConfiguration().registering([]).decoders.isEmpty)
}

@Test func rulesRegisterOneDecoderEvenAcrossCalls() throws {
    let configuration = CerebroConfiguration().registering([rule()]).registering([rule(direction: .request)])

    #expect(configuration.decoders.count == 1)
    let decoder = try #require(configuration.decoders.first as? ProtoDecoder)
    #expect(decoder.rules.count == 2)
}

@Test func registeringKeepsOtherDecoders() {
    struct Other: BodyDecoder {
        func decode(_ body: Data, context: BodyContext) -> Data? { nil }
    }

    let configuration = CerebroConfiguration(decoders: [Other()]).registering([rule()])

    #expect(configuration.decoders.count == 2)
    #expect(configuration.decoders.first is Other)
}
