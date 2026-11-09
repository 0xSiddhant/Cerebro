import Foundation
import Testing
import os
@testable import CerebroCore

private let socket = SocketIdentity(id: UUID(), source: .external, name: "wss://example.com/feed")

private func redactor(_ jsonKeys: Set<String>) -> Redactor {
    Redactor(rules: RedactionRules(jsonKeys: jsonKeys))
}

private func capture(
    _ payload: SocketPayload,
    limit: Int,
    jsonKeys: Set<String>,
    didFail: Bool = false,
    backlog: SocketBacklog = SocketBacklog(frameLimit: 10, byteLimit: 1_048_576),
    on identity: SocketIdentity = socket
) throws -> RawSocketActivity {
    let captured = OSAllocatedUnfairLock<RawSocketActivity?>(initialState: nil)
    let engine = SocketCaptureEngine(bodyLimit: limit, backlog: backlog, redactor: redactor(jsonKeys)) { activity in
        captured.withLock { $0 = activity }
    }
    engine.submit(payload, .received, didFail: didFail, on: identity)
    let activity = captured.withLock { $0 }
    return try #require(activity)
}

private func frame(
    _ payload: SocketPayload,
    limit: Int = 1_000,
    jsonKeys: Set<String> = [],
    didFail: Bool = false,
    backlog: SocketBacklog = SocketBacklog(frameLimit: 10, byteLimit: 1_048_576)
) throws -> SocketFrame {
    let activity = try capture(payload, limit: limit, jsonKeys: jsonKeys, didFail: didFail, backlog: backlog)
    let builder = SocketActivityBuilder(
        processor: BodyProcessor(limit: limit, decoders: [], redactor: redactor(jsonKeys))
    )
    guard case .frame(let frame) = builder.item(from: activity) else {
        Issue.record("expected a frame")
        throw CancellationError()
    }
    return frame
}

private func builder(jsonKeys: Set<String> = []) -> SocketActivityBuilder {
    SocketActivityBuilder(processor: BodyProcessor(limit: 1_000, decoders: [], redactor: redactor(jsonKeys)))
}

private func redacted(_ event: SocketEvent, jsonKeys: Set<String>) -> SocketEvent? {
    let date = Date(timeIntervalSince1970: 1)
    let activity = RawSocketActivity(socket: socket, content: .event(event), date: date)
    guard case .event(let result, _) = builder(jsonKeys: jsonKeys).item(from: activity) else { return nil }
    return result
}

@Test func textFrameKeepsItsBytesAndKind() throws {
    let frame = try frame(.text("héllo"))

    #expect(frame.kind == .text)
    #expect(frame.direction == .received)
    #expect(frame.byteCount == 6)
    #expect(frame.payload?.data == Data("héllo".utf8))
}

@Test func binaryFrameKeepsItsBytesAndKind() throws {
    let frame = try frame(.binary(Data([1, 2, 3])))

    #expect(frame.kind == .binary)
    #expect(frame.payload?.data == Data([1, 2, 3]))
}

@Test func compressedBinaryFrameShowsDecompressed() throws {
    let plain = Data(#"{"price":42}"#.utf8)

    let frame = try frame(.binary(try Fixtures.gzip(plain)))

    #expect(frame.payload?.data == plain)
    #expect(frame.payload?.compression == .gzip)
    #expect(frame.payload?.isDecompressed == true)
}

@Test func textThatStartsLikeZlibIsntLabelledCompressed() throws {
    let frame = try frame(.text("x^2 + y^2"))

    #expect(frame.payload?.compression == nil)
    #expect(frame.payload?.data == Data("x^2 + y^2".utf8))
}

@Test func binaryFrameOverTheCapIsTruncatedAndKeepsItsFullSize() throws {
    let frame = try frame(.binary(Data(count: 50)), limit: 10)

    #expect(frame.byteCount == 50)
    guard case .truncated(let kept) = frame.payload?.content else {
        Issue.record("expected a truncated payload")
        return
    }
    #expect(kept.count == 10)
}

@Test func textFrameOverTheCapIsTruncatedAndKeepsItsFullSize() throws {
    let frame = try frame(.text(String(repeating: "a", count: 50)), limit: 10)

    #expect(frame.byteCount == 50)
    guard case .truncated(let kept) = frame.payload?.content else {
        Issue.record("expected a truncated payload")
        return
    }
    #expect(kept.count == 10)
}

@Test func theCapIsAppliedBeforeAFrameIsQueued() throws {
    let binary = try capture(.binary(Data(count: 5_000)), limit: 10, jsonKeys: [])
    let text = try capture(.text(String(repeating: "a", count: 5_000)), limit: 10, jsonKeys: [])

    #expect(binary.backlogBytes == 10)
    #expect(text.backlogBytes == 10)
}

@Test func aFrameTheBacklogCantHoldKeepsOnlyItsSize() throws {
    let full = SocketBacklog(frameLimit: 0, byteLimit: 1_000)

    let frame = try frame(.text("hello"), backlog: full)

    #expect(frame.byteCount == 5)
    #expect(frame.payload?.content == .notStored)
}

@Test func aFailedSendKeepsItsFlag() throws {
    #expect(try frame(.text("x"), didFail: true).didFail)
    #expect(try !frame(.text("x")).didFail)
}

@Test func unparseableJSONFrameIsWithheldWhenJSONKeysAreConfigured() throws {
    let frame = try frame(.text(#"{"token":"#), jsonKeys: ["token"])

    #expect(frame.payload?.content == .withheld)
}

@Test func configuredJSONKeysAreRedactedInFrames() throws {
    let frame = try frame(.text(#"{"token":"secret"}"#), jsonKeys: ["token"])

    let text = try #require(frame.payload?.data.flatMap { String(data: $0, encoding: .utf8) })
    #expect(!text.contains("secret"))
    #expect(text.contains(Redactor.marker))
}

@Test func prefixedJSONNamingAKeyIsWithheld() throws {
    let frame = try frame(.text(#"42["auth",{"token":"secret"}]"#), jsonKeys: ["token"])

    #expect(frame.payload?.content == .withheld)
}

@Test func prefixedJSONNamingNoKeyIsKept() throws {
    let text = #"42["ping",{"count":1}]"#

    #expect(try frame(.text(text), jsonKeys: ["token"]).payload?.data == Data(text.utf8))
}

@Test func prefixedJSONIsKeptWhenNoKeysAreConfigured() throws {
    let text = #"42["auth",{"token":"secret"}]"#

    #expect(try frame(.text(text)).payload?.data == Data(text.utf8))
}

@Test func aTextFrameCutMidCharacterIsStillCheckedForAKey() throws {
    let text = "the token é"

    #expect(try frame(.text(text), limit: text.utf8.count - 1, jsonKeys: ["token"]).payload?.content == .withheld)
}

@Test func binaryBytesCantNameAKey() throws {
    let bytes = Data([0xFF, 0xFE, 0x01])

    #expect(try frame(.binary(bytes), jsonKeys: ["token"]).payload?.data == bytes)
}

@Test func emptyFrameHasNoPayload() throws {
    let frame = try frame(.text(""))

    #expect(frame.payload == nil)
    #expect(frame.byteCount == 0)
}

@Test func eventsPassThroughWithTheirDate() {
    let date = Date(timeIntervalSince1970: 9)
    let activity = RawSocketActivity(socket: socket, content: .event(.ping), date: date)

    #expect(builder().item(from: activity) == .event(.ping, date: date))
}

@Test func eventTextNamingAKeyIsRedacted() {
    #expect(
        redacted(.closed(code: 4001, reason: "bad token abc"), jsonKeys: ["token"])
            == .closed(code: 4001, reason: Redactor.marker)
    )
    #expect(redacted(.failed("token expired"), jsonKeys: ["token"]) == .failed(Redactor.marker))
    #expect(redacted(.stateChanged("token set"), jsonKeys: ["token"]) == .stateChanged(Redactor.marker))
}

@Test func eventTextNamingNoKeyIsKept() {
    #expect(redacted(.closed(code: 1000, reason: "done"), jsonKeys: ["token"]) == .closed(code: 1000, reason: "done"))
    #expect(redacted(.closed(code: nil, reason: nil), jsonKeys: ["token"]) == .closed(code: nil, reason: nil))
    #expect(redacted(.failed("token expired"), jsonKeys: []) == .failed("token expired"))
}

/// Decodes only frames whose URL has this host and path, as a rule naming them does.
private struct AddressDecoder: BodyDecoder {
    let host: String
    let path: String

    func decode(_ body: Data, context: BodyContext) -> Data? {
        context.url?.host == host && context.url?.path == path ? Data("{}".utf8) : nil
    }
}

@Test(arguments: [
    ("wss://api.example.com/feed", "/feed"),
    ("api.example.com:443", ""),
    ("api.example.com", ""),
])
func aRuleCanMatchTheHostOfEachKindOfSocketName(name: String, path: String) throws {
    let identity = SocketIdentity(id: UUID(), source: .external, name: name)
    let activity = try capture(.binary(Data([1])), limit: 1_000, jsonKeys: [], on: identity)
    let decoder = AddressDecoder(host: "api.example.com", path: path)
    let builder = SocketActivityBuilder(
        processor: BodyProcessor(limit: 1_000, decoders: [decoder], redactor: redactor([]))
    )

    guard case .frame(let frame) = builder.item(from: activity) else {
        Issue.record("expected a frame")
        return
    }

    #expect(frame.payload?.isDecoded == true)
}
