import Foundation
import SwiftProtobuf
import Testing
@testable import CerebroCore
@testable import CerebroProto

private let quotes = URL(string: "https://api.example.com/v1/quotes")

private func response(contentType: String? = nil) -> BodyContext {
    BodyContext(url: quotes, method: "GET", contentType: contentType, direction: .response)
}

private func sourceContext(_ fileName: String) throws -> Data {
    var message = Google_Protobuf_SourceContext()
    message.fileName = fileName
    return try message.serializedBytes()
}

private func decoder(stripPrefixBytes: Int = 0) -> ProtoDecoder {
    ProtoDecoder(rules: [
        ProtoRule(
            direction: .response,
            messageType: Google_Protobuf_SourceContext.self,
            stripPrefixBytes: stripPrefixBytes
        )
    ])
}

private func grpcFrame(_ payload: Data, flag: UInt8 = 0) -> Data {
    let length = UInt32(payload.count).bigEndian
    return Data([flag]) + withUnsafeBytes(of: length) { Data($0) } + payload
}

@Test func aRealMessageDecodesToJSONWithProtoFieldNames() throws {
    let json = try #require(decoder().decode(try sourceContext("quote.proto"), context: response()))

    #expect(String(data: json, encoding: .utf8) == #"{"file_name":"quote.proto"}"#)
}

@Test func nothingMatchingReturnsNilAndCountsNothing() throws {
    let request = BodyContext(url: quotes, method: "POST", contentType: nil, direction: .request)
    let decoder = decoder()

    #expect(decoder.decode(try sourceContext("a"), context: request) == nil)
    #expect(decoder.mappings.first?.matchCount == 0)
}

@Test func bytesThatArentTheMessageReturnNilButAreStillClaimed() {
    let decoder = decoder()
    let garbage = Data([0xFF, 0xFF, 0xFF, 0xFF])

    #expect(decoder.decode(garbage, context: response()) == nil)
    #expect(decoder.claims(response()))
}

@Test func thePrefixIsStrippedBeforeDecoding() throws {
    let framed = Data([0xAA, 0xBB]) + (try sourceContext("framed"))

    let json = try #require(decoder(stripPrefixBytes: 2).decode(framed, context: response()))

    #expect(String(data: json, encoding: .utf8)?.contains("framed") == true)
}

@Test func aBodyShorterThanThePrefixDoesntDecode() {
    #expect(decoder(stripPrefixBytes: 5).decode(Data([0x01]), context: response()) == nil)
}

@Test func aGRPCWebBodyDecodesAfterItsHeader() throws {
    let body = grpcFrame(try sourceContext("grpc"))

    let json = try #require(
        decoder(stripPrefixBytes: 5).decode(body, context: response(contentType: "application/grpc-web+proto"))
    )

    #expect(String(data: json, encoding: .utf8)?.contains("grpc") == true)
}

@Test func aGRPCWebBodyIgnoresATrailersFrameAfterTheMessage() throws {
    let body = grpcFrame(try sourceContext("grpc")) + grpcFrame(Data("grpc-status:0".utf8), flag: 0x80)

    let json = try #require(
        decoder(stripPrefixBytes: 5).decode(body, context: response(contentType: "application/grpc-web+proto"))
    )

    #expect(String(data: json, encoding: .utf8) == #"{"file_name":"grpc"}"#)
}

@Test func theFirstMatchingRuleWins() throws {
    let decoder = ProtoDecoder(rules: [
        ProtoRule(name: "first", direction: .response, messageType: Google_Protobuf_SourceContext.self),
        ProtoRule(name: "second", direction: .response, messageType: Google_Protobuf_Struct.self),
    ])

    _ = decoder.decode(try sourceContext("a"), context: response())

    #expect(decoder.mappings.map(\.matchCount) == [1, 0])
}

@Test func codeRulesAreCheckedBeforeFileRulesWhateverOrderTheyArrive() throws {
    let decoder = ProtoDecoder(rules: [
        ProtoRule(name: "file", direction: .response, messageType: Google_Protobuf_Struct.self, source: .file),
        ProtoRule(name: "code", direction: .response, messageType: Google_Protobuf_SourceContext.self),
    ])

    let json = try #require(decoder.decode(try sourceContext("a"), context: response()))

    #expect(decoder.mappings.map(\.name) == ["code", "file"])
    #expect(String(data: json, encoding: .utf8)?.contains("file_name") == true)
}

@Test func fileRulesKeepTheirOrder() {
    let decoder = ProtoDecoder(rules: [
        ProtoRule(name: "one", direction: .response, messageType: Google_Protobuf_Struct.self, source: .file),
        ProtoRule(name: "two", direction: .response, messageType: Google_Protobuf_Struct.self, source: .file),
    ])

    #expect(decoder.mappings.map(\.name) == ["one", "two"])
}

@Test func mappingsDescribeEachRule() throws {
    let rule = ProtoRule(
        name: "Quote",
        match: .init(host: "api.example.com", pathPrefix: "/v1"),
        methods: ["get"],
        direction: .response,
        messageType: Google_Protobuf_SourceContext.self,
        source: .file
    )

    let mapping = try #require(ProtoDecoder(rules: [rule]).mappings.first)

    #expect(mapping.name == "Quote")
    #expect(mapping.matcher == "GET api.example.com /v1*")
    #expect(mapping.direction == "Response")
    #expect(mapping.messageType == "google.protobuf.SourceContext")
    #expect(mapping.source == .file)
}

@Test func matchesAreCountedEvenWhenDecodingFails() {
    let decoder = decoder()

    _ = decoder.decode(Data([0xFF, 0xFF]), context: response())

    #expect(decoder.mappings.first?.matchCount == 1)
}

@Test func aRealMessageGoesThroughThePipelineAndIsRedacted() throws {
    let processor = BodyProcessor(
        limit: 1_000,
        decoders: [decoder()],
        redactor: Redactor(rules: RedactionRules(jsonKeys: ["file_name"]))
    )

    let body = try #require(
        processor.process(RawBody(data: try sourceContext("secret.proto"), limit: 1_000), context: response())
    )

    #expect(body.isDecoded)
    #expect(body.rawData == nil)
    let stored = String(data: try #require(body.data), encoding: .utf8)
    #expect(stored == #"{"file_name":"[redacted]"}"#)
    #expect(BodyFormatter.raw(body).contains("secret") == false)
}

@Test func aBinaryFrameDecodesThroughTheSameRules() throws {
    let rule = ProtoRule(direction: .socketIncoming, messageType: Google_Protobuf_SourceContext.self)
    let processor = BodyProcessor(
        limit: 1_000, decoders: [ProtoDecoder(rules: [rule])], redactor: Redactor(rules: .init()))
    let frame = BodyContext(
        url: quotes, method: "SOCKET", contentType: nil, direction: .response, carrier: .binaryFrame)

    let body = processor.process(RawBody(data: try sourceContext("tick"), limit: 1_000), context: frame)

    #expect(body?.isDecoded == true)
}

@Test func bytesThatAreAllUnknownFieldsDontCountAsDecoded() {
    // Field 15 as a varint, which `SourceContext` doesn't have.
    #expect(decoder().decode(Data([0x78, 0x01]), context: response()) == nil)
}

@Test func anEmptyMessageStillDecodes() throws {
    let json = try #require(decoder(stripPrefixBytes: 5).decode(Data(count: 5), context: response()))

    #expect(String(data: json, encoding: .utf8) == "{}")
}

@Test func aBodyOverTheCapStillCountsAsAMatch() {
    let decoder = decoder()
    let processor = BodyProcessor(limit: 3, decoders: [decoder], redactor: Redactor(rules: .init()))

    let body = processor.process(RawBody(data: Data(count: 10), limit: 3), context: response())

    #expect(body?.undecoded == .truncated)
    #expect(decoder.mappings.first?.matchCount == 1)
}

@Test func aJSONErrorFromAProtobufEndpointStaysJSON() throws {
    let processor = BodyProcessor(
        limit: 1_000,
        decoders: [decoder()],
        redactor: Redactor(rules: RedactionRules(jsonKeys: ["token"]))
    )
    let error = Data(#"{"error":"expired","token":"secret"}"#.utf8)

    let body = try #require(
        processor.process(
            RawBody(data: error, limit: 1_000),
            context: response(contentType: "application/json; charset=utf-8")
        )
    )

    #expect(body.undecoded == nil)
    #expect(!body.isDecoded)
    let stored = String(data: try #require(body.data), encoding: .utf8)
    #expect(stored?.contains("expired") == true)
    #expect(stored?.contains("secret") == false)
}
