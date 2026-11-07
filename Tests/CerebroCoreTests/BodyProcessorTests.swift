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

@Test func withNoJSONKeysABodyOverTheCapIsStillStoredTruncated() {
    let body = processor(limit: 10).process(
        Fixtures.raw(json, limit: 10),
        context: Fixtures.context(contentType: "application/json")
    )

    #expect(body?.content == .truncated(json.prefix(10)))
}
