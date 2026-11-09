import Foundation
import Testing
@testable import CerebroCore

/// Counts how many bodies it was asked to decode, and never decodes one.
private final class CountingDecoder: BodyDecoder, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var calls: Int {
        lock.withLock { count }
    }

    func decode(_ body: Data, context: BodyContext) -> Data? {
        lock.withLock { count += 1 }
        return nil
    }
}

private func processor(
    limit: Int = 1_000,
    decoders: [any BodyDecoder] = [],
    rules: RedactionRules = RedactionRules()
) -> BodyProcessor {
    BodyProcessor(limit: limit, decoders: decoders, redactor: Redactor(rules: rules))
}

private let json = Data(#"{"password":"secret","name":"ada"}"#.utf8)

/// Claims every body, as a decoder with a matching rule does, and decodes it to `output` if there is one.
private struct ClaimingDecoder: BodyDecoder {
    let output: Data?

    func decode(_ body: Data, context: BodyContext) -> Data? {
        output
    }

    func claims(_ context: BodyContext) -> Bool {
        true
    }
}

private let protobufBytes = Data([0x0A, 0x03, 0x61, 0x62, 0x63])

@Test(arguments: [
    "application/x-protobuf",
    "application/protobuf",
    "application/grpc",
    "application/grpc-web+proto",
    "Application/X-Protobuf; messageType=Quote",
])
func protobufContentTypesWithNoRuleAreMarked(contentType: String) {
    let body = processor().process(Fixtures.raw(protobufBytes), context: Fixtures.context(contentType: contentType))

    #expect(body?.undecoded == .noRule)
    #expect(body?.isDecoded == false)
}

@Test(arguments: ["application/json", "application/octet-stream", "text/plain"])
func otherContentTypesAreNotMarkedAsProtobuf(contentType: String) {
    let body = processor().process(Fixtures.raw(protobufBytes), context: Fixtures.context(contentType: contentType))

    #expect(body?.undecoded == nil)
}

@Test func protobufWithNoRuleShowsAsHexEvenWhenItPassesForText() throws {
    let body = try #require(
        processor().process(Fixtures.raw(protobufBytes), context: Fixtures.context(contentType: "application/grpc"))
    )

    #expect(BodyFormatter.raw(body) == "0a03616263")
    #expect(BodyFormatter.pretty(body) == "0a03616263")
}

@Test func aBodyOverTheCapIsNeverDecodedAndIsMarkedTruncated() throws {
    let decoder = CountingDecoder()
    let raw = RawBody(data: protobufBytes, limit: 3)

    let body = try #require(
        processor(limit: 3, decoders: [decoder])
            .process(raw, context: Fixtures.context(contentType: "application/x-protobuf"))
    )

    #expect(decoder.calls == 0)
    #expect(body.undecoded == .truncated)
    if case .truncated = body.content {} else { Issue.record("expected a truncated body") }
}

@Test func aClaimedBodyOverTheCapIsMarkedTruncatedWithoutAProtobufContentType() {
    let raw = RawBody(data: protobufBytes, limit: 3)

    let body = processor(limit: 3, decoders: [ClaimingDecoder(output: nil)]).process(raw, context: Fixtures.context())

    #expect(body?.undecoded == .truncated)
}

@Test func aTruncatedProtobufBodyIsWithheldWhenJSONKeysAreSet() {
    let raw = RawBody(data: protobufBytes, limit: 3)

    let body = processor(limit: 3, rules: RedactionRules(jsonKeys: ["password"]))
        .process(raw, context: Fixtures.context(contentType: "application/x-protobuf"))

    #expect(body?.content == .withheld)
    #expect(body?.undecoded == .truncated)
}

@Test func protobufWithNoRuleIsWithheldWhenJSONKeysAreSet() {
    let body = processor(rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(protobufBytes), context: Fixtures.context(contentType: "application/x-protobuf"))

    #expect(body?.content == .withheld)
    #expect(body?.undecoded == .noRule)
}

@Test func aClaimedBodyThatWontDecodeIsMarkedFailed() {
    let body = processor(decoders: [ClaimingDecoder(output: nil)])
        .process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.undecoded == .failed)
    #expect(body?.isDecoded == false)
}

@Test func anUnclaimedBinaryBodyStaysUnmarked() {
    let body = processor().process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.undecoded == nil)
}

@Test func aDecodedBodyKeepsItsBytesForTheHexView() throws {
    let decoded = Data(#"{"name":"ada"}"#.utf8)

    let body = try #require(
        processor(decoders: [ClaimingDecoder(output: decoded)])
            .process(Fixtures.raw(protobufBytes), context: Fixtures.context())
    )

    #expect(body.isDecoded)
    #expect(body.rawData == protobufBytes)
    #expect(BodyFormatter.raw(body) == "0a03616263")
}

@Test func aDecodedBodyDropsItsBytesWheneverJSONKeysAreSet() {
    // An unknown field could hold the secret, and it's in these bytes but never in the JSON.
    let decoded = Data(#"{"name":"ada"}"#.utf8)

    let body = processor(decoders: [ClaimingDecoder(output: decoded)], rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.isDecoded == true)
    #expect(body?.rawData == nil)
}

@Test func aDecodedBodyDropsItsBytesWhenRedactionChangesIt() throws {
    let body = try #require(
        processor(decoders: [ClaimingDecoder(output: json)], rules: RedactionRules(jsonKeys: ["password"]))
            .process(Fixtures.raw(protobufBytes), context: Fixtures.context())
    )

    #expect(body.isDecoded)
    #expect(body.rawData == nil)
    #expect(BodyFormatter.raw(body).contains("secret") == false)
    #expect(BodyFormatter.raw(body).contains("0a03") == false)
}

@Test func decodedOutputIsRedactedEvenWhenItDoesntLookLikeAnObject() {
    let decoded = Data(#""just text""#.utf8)

    let body = processor(decoders: [ClaimingDecoder(output: decoded)], rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.isDecoded == true)
    #expect(body?.data == decoded)
}

@Test func decodedJSONOverTheCapIsNotKeptAndTheBodyStaysHex() throws {
    let decoded = Data(repeating: UInt8(ascii: "a"), count: 11)

    let body = try #require(
        processor(limit: 10, decoders: [ClaimingDecoder(output: decoded)])
            .process(Fixtures.raw(protobufBytes), context: Fixtures.context())
    )

    #expect(!body.isDecoded)
    #expect(body.undecoded == .truncated)
    #expect(body.data == protobufBytes)
    #expect(body.rawData == nil)
}

@Test func decodedJSONAtTheCapIsKept() {
    let decoded = Data(repeating: UInt8(ascii: "1"), count: 10)

    let body = processor(limit: 10, decoders: [ClaimingDecoder(output: decoded)])
        .process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.isDecoded == true)
    #expect(body?.data == decoded)
}

@Test func decodedJSONOverTheCapIsWithheldWhenJSONKeysAreSet() {
    let decoded = Data(repeating: UInt8(ascii: "a"), count: 11)

    let body = processor(
        limit: 10, decoders: [ClaimingDecoder(output: decoded)], rules: RedactionRules(jsonKeys: ["a"])
    )
    .process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.content == .withheld)
}

@Test(arguments: [
    "application/grpc+json",
    "application/grpc-web+json",
    "application/grpc-web-text",
    "application/grpc-web-text+proto",
])
func gRPCJSONAndTextFormsAreNotBinaryProtobuf(contentType: String) {
    let body = processor().process(Fixtures.raw(protobufBytes), context: Fixtures.context(contentType: contentType))

    #expect(body?.undecoded == nil)
}

@Test func aParameterCantMakeProtobufLookLikeText() {
    let context = Fixtures.context(contentType: "application/x-protobuf; messageType=json.Quote")

    #expect(processor().process(Fixtures.raw(protobufBytes), context: context)?.undecoded == .noRule)
}

@Test func gRPCWebTextIsWithheldWhenJSONKeysAreSet() {
    // Base64 hides the field names, so a search of the text would find nothing and store it.
    let body = processor(rules: RedactionRules(jsonKeys: ["password"]))
        .process(
            Fixtures.raw(Data("AAAAAAU=".utf8)), context: Fixtures.context(contentType: "application/grpc-web-text"))

    #expect(body?.content == .withheld)
}
