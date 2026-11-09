import Foundation
import Testing
@testable import CerebroCore

/// Records what it was given, and turns anything it sees into a fixed JSON body.
private final class RecordingDecoder: BodyDecoder, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Data] = []
    let output: Data?

    init(output: Data?) {
        self.output = output
    }

    var received: [Data] {
        lock.withLock { seen }
    }

    func decode(_ body: Data, context: BodyContext) -> Data? {
        lock.withLock { seen.append(body) }
        return output
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

@Test func emptyBodyProducesNothing() {
    #expect(processor().process(RawBody(limit: 10), context: Fixtures.context()) == nil)
}

@Test func plainBodyPassesThroughUntouched() {
    let body = processor().process(Fixtures.raw(json), context: Fixtures.context())

    #expect(body?.content == .complete(json))
    #expect(body?.compression == nil)
    #expect(body?.isDecompressed == false)
}

@Test func bodyOverTheCapIsStoredTruncatedAndKeepsItsFullSize() {
    let body = processor(limit: 10).process(Fixtures.raw(json, limit: 10), context: Fixtures.context())

    #expect(body?.content == .truncated(json.prefix(10)))
    #expect(body?.byteCount == json.count)
}

@Test func compressedBodyIsDecompressedForDisplay() throws {
    let body = processor().process(Fixtures.raw(try Fixtures.gzip(json)), context: Fixtures.context())

    #expect(body?.content == .complete(json))
    #expect(body?.compression == .gzip)
    #expect(body?.isDecompressed == true)
}

@Test func requestHeaderNamesTheCompression() throws {
    let brotli = Data("not really brotli".utf8)

    let body = processor().process(Fixtures.raw(brotli), context: Fixtures.context(), declared: .brotli)

    #expect(body?.compression == .brotli)
    #expect(body?.isDecompressed == false)
    #expect(body?.content == .complete(brotli))
}

@Test func zstdIsFlaggedAndShownRaw() {
    let zstd = Data([0x28, 0xB5, 0x2F, 0xFD, 0x01, 0x02])

    let body = processor().process(Fixtures.raw(zstd), context: Fixtures.context())

    #expect(body?.compression == .zstd)
    #expect(body?.isDecompressed == false)
    #expect(body?.content == .complete(zstd))
}

@Test func smallBodyThatExpandsPastTheCapIsTruncatedAndSkipsDecoders() throws {
    let decoder = RecordingDecoder(output: Data("{}".utf8))
    let bomb = try Fixtures.gzip(Data(count: 10_000_000))

    let body = processor(limit: 1_000, decoders: [decoder]).process(
        Fixtures.raw(bomb, limit: 1_000_000),
        context: Fixtures.context()
    )

    #expect(body?.data?.count == 1_000)
    if case .truncated = body?.content {} else { Issue.record("expected a truncated body") }
    #expect(decoder.received.isEmpty)
}

@Test func decodersReceivePlainBytesAndTheirOutputIsRedacted() throws {
    let decoder = RecordingDecoder(output: json)
    let binary = Data([0x01, 0x02, 0x03, 0x04])

    let body = processor(
        decoders: [decoder],
        rules: RedactionRules(jsonKeys: ["password"])
    )
    .process(Fixtures.raw(try Fixtures.gzip(binary)), context: Fixtures.context())

    #expect(decoder.received == [binary])
    let stored = try #require(body?.data)
    #expect(String(data: stored, encoding: .utf8)?.contains("secret") == false)
}

@Test func theFirstDecoderThatAppliesWins() {
    let declines = RecordingDecoder(output: nil)
    let applies = RecordingDecoder(output: Data("{}".utf8))
    let unused = RecordingDecoder(output: Data("[]".utf8))

    let body = processor(decoders: [declines, applies, unused]).process(Fixtures.raw(json), context: Fixtures.context())

    #expect(body?.content == .complete(Data("{}".utf8)))
    #expect(unused.received.isEmpty)
}

@Test func withNoJSONKeysNothingIsParsedOrChanged() {
    let spaced = Data("  { \"a\" :   1 }".utf8)

    let body = processor().process(Fixtures.raw(spaced), context: Fixtures.context(contentType: "application/json"))

    #expect(body?.content == .complete(spaced))
}

@Test func withJSONKeysStoredBodyIsTheRedactedOne() throws {
    let body = processor(rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(json), context: Fixtures.context())

    let stored = try #require(body?.data)
    let text = try #require(String(data: stored, encoding: .utf8))
    #expect(!text.contains("secret"))
    #expect(text.contains(Redactor.marker))
    #expect(text.contains("ada"))
}

@Test func withJSONKeysABodyOverTheCapIsWithheld() {
    let body = processor(limit: 10, rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(json, limit: 10), context: Fixtures.context())

    #expect(body?.content == .withheld)
    #expect(body?.data == nil)
    #expect(body?.byteCount == json.count)
}

@Test func withJSONKeysAMalformedBodyIsWithheld() {
    let malformed = Data(#"{"password":"secret""#.utf8)

    let body = processor(rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(malformed), context: Fixtures.context())

    #expect(body?.content == .withheld)
}

@Test func withJSONKeysABodyTheContentTypeCallsJSONIsWithheldIfItCantBeParsed() {
    let unreadable = Data([0x28, 0xB5, 0x2F, 0xFD, 0x01])

    let body = processor(rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(unreadable), context: Fixtures.context(contentType: "application/json"))

    #expect(body?.content == .withheld)
}

@Test func withJSONKeysABodyThatIsNotJSONIsLeftAlone() {
    let text = Data("plain text".utf8)

    let body = processor(rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(text), context: Fixtures.context(contentType: "text/plain"))

    #expect(body?.content == .complete(text))
}

private let formContentType = "application/x-www-form-urlencoded"

private func processed(
    _ sent: Data,
    contentType: String?,
    keys: Set<String> = ["password"],
    limit: Int = 1_000
) -> CapturedBody? {
    processor(limit: limit, rules: RedactionRules(jsonKeys: keys))
        .process(Fixtures.raw(sent, limit: limit), context: Fixtures.context(contentType: contentType))
}

private func processed(
    _ sent: String,
    contentType: String?,
    keys: Set<String> = ["password"],
    limit: Int = 1_000
) -> CapturedBody? {
    processed(Data(sent.utf8), contentType: contentType, keys: keys, limit: limit)
}

@Test func formFieldsAreRedactedAndTheRestKeepTheirExactBytesInOrder() {
    let body = processed("a=1%202&password=hunter2&b=c+d&&password=again&empty=", contentType: formContentType)

    #expect(body?.content == .complete(Data("a=1%202&password=[redacted]&b=c+d&&password=[redacted]&empty=".utf8)))
}

@Test func formContentTypeMatchesWhateverItsCaseOrCharset() {
    let body = processed("password=hunter2", contentType: "Application/X-WWW-Form-URLEncoded; charset=UTF-8")

    #expect(body?.content == .complete(Data("password=[redacted]".utf8)))
}

@Test func formFieldNamesAreComparedDecodedAndWithoutCase() {
    let body = processed(
        "p%61ssword=a&PASSWORD=b&first+name=c&first%20name=d&other=e",
        contentType: formContentType,
        keys: ["password", "First Name"]
    )

    let expected = "p%61ssword=[redacted]&PASSWORD=[redacted]&first+name=[redacted]&first%20name=[redacted]&other=e"
    #expect(body?.content == .complete(Data(expected.utf8)))
}

@Test func aFormFieldNotNamedByARuleIsLeftAloneEvenIfItsValueHoldsAKey() {
    let sent = "note=my+password+is+long&password"

    #expect(processed(sent, contentType: formContentType)?.content == .complete(Data(sent.utf8)))
}

@Test func aTruncatedFormBodyIsWithheld() {
    let body = processed("a=1&password=hunter2", contentType: formContentType, limit: 5)

    #expect(body?.content == .withheld)
}

@Test func jsonSentUnderAFormContentTypeIsStillRedactedByKey() throws {
    let stored = try #require(processed(json, contentType: formContentType)?.data)

    #expect(String(data: stored, encoding: .utf8)?.contains("secret") == false)
}

@Test func aFormWithNoContentTypeIsWithheldIfItNamesAKey() {
    #expect(processed("user=ada&password=hunter2", contentType: nil)?.content == .withheld)
    #expect(processed("user=ada&p%61ssword=hunter2", contentType: nil)?.content == .withheld)
}

@Test func aFormWithNoContentTypeThatNamesNoKeyIsKept() {
    let sent = "user=ada&page=2"

    #expect(processed(sent, contentType: nil)?.content == .complete(Data(sent.utf8)))
}

@Test func plainTextThatNamesAKeyIsWithheld() {
    #expect(processed("the PassWord is hunter2", contentType: "text/plain")?.content == .withheld)
}

@Test func withNoJSONKeysFormAndTextBodiesAreLeftAlone() {
    let form = "password=hunter2"
    let text = "the password is hunter2"

    #expect(processed(form, contentType: formContentType, keys: [])?.content == .complete(Data(form.utf8)))
    #expect(processed(text, contentType: "text/plain", keys: [])?.content == .complete(Data(text.utf8)))
    #expect(processed(form, contentType: nil, keys: [])?.content == .complete(Data(form.utf8)))
}

@Test func textCutMidCharacterIsStillCheckedForAKey() {
    let sent = Data("the password é".utf8)

    #expect(processed(sent, contentType: "text/plain", limit: sent.count - 1)?.content == .withheld)
}

@Test func textCutMidCharacterThatNamesNoKeyIsStoredTruncated() {
    let sent = Data("nothing here é".utf8)
    let limit = sent.count - 1

    #expect(processed(sent, contentType: "text/plain", limit: limit)?.content == .truncated(sent.prefix(limit)))
}

@Test func binaryBodiesAreStoredEvenIfTheirBytesHoldAKey() {
    let image = Data([0x89, 0x50, 0x4E, 0x47, 0xFF]) + Data("id".utf8)

    #expect(processed(image, contentType: "image/png", keys: ["id"])?.content == .complete(image))
    #expect(processed(image, contentType: nil, keys: ["id"])?.content == .complete(image))
}

@Test func truncatedBinaryBodiesStayStored() {
    let image = Data([0x89, 0x50, 0x4E, 0x47, 0xFF]) + Data("id and more".utf8)

    #expect(processed(image, contentType: "image/png", keys: ["id"], limit: 8)?.content == .truncated(image.prefix(8)))
}

@Test func withNoJSONKeysABodyOverTheCapIsStillStoredTruncated() {
    let body = processor(limit: 10).process(
        Fixtures.raw(json, limit: 10),
        context: Fixtures.context(contentType: "application/json")
    )

    #expect(body?.content == .truncated(json.prefix(10)))
}

@Test func aTruncatedBodyDoesntHoldOnToTheRest() {
    let whole = Data(count: 1_000)

    let body = RawBody(data: whole, limit: 10)

    #expect(body.data.count == 10)
    #expect(body.isTruncated)
    #expect(body.data.withUnsafeBytes(\.baseAddress) != whole.withUnsafeBytes(\.baseAddress))
}

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
    let decoder = RecordingDecoder(output: Data("{}".utf8))
    let raw = RawBody(data: protobufBytes, limit: 3)

    let body = try #require(
        processor(limit: 3, decoders: [decoder])
            .process(raw, context: Fixtures.context(contentType: "application/x-protobuf"))
    )

    #expect(decoder.received.isEmpty)
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

@Test func aDecodedBodyKeepsItsBytesWhenRedactionChangesNothing() {
    let decoded = Data(#"{"name":"ada"}"#.utf8)

    let body = processor(decoders: [ClaimingDecoder(output: decoded)], rules: RedactionRules(jsonKeys: ["password"]))
        .process(Fixtures.raw(protobufBytes), context: Fixtures.context())

    #expect(body?.rawData == protobufBytes)
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
