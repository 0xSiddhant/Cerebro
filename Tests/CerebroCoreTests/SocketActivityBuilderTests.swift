import Foundation
import Testing
@testable import CerebroCore

private let socket = SocketIdentity(id: UUID(), source: .external, name: "wss://example.com/feed")

private func builder(limit: Int = 1_000, jsonKeys: Set<String> = []) -> SocketActivityBuilder {
    SocketActivityBuilder(
        processor: BodyProcessor(
            limit: limit,
            decoders: [],
            redactor: Redactor(rules: RedactionRules(jsonKeys: jsonKeys))
        )
    )
}

private func frame(_ payload: SocketPayload, with builder: SocketActivityBuilder) throws -> SocketFrame {
    let activity = RawSocketActivity(
        socket: socket, content: .frame(.received, payload), date: Date(timeIntervalSince1970: 5))
    guard case .frame(let frame) = builder.item(from: activity) else {
        Issue.record("expected a frame")
        throw CancellationError()
    }
    return frame
}

@Test func textFrameKeepsItsBytesAndKind() throws {
    let frame = try frame(.text("héllo"), with: builder())

    #expect(frame.kind == .text)
    #expect(frame.direction == .received)
    #expect(frame.byteCount == 6)
    #expect(frame.date == Date(timeIntervalSince1970: 5))
    #expect(frame.payload?.data == Data("héllo".utf8))
}

@Test func binaryFrameKeepsItsBytesAndKind() throws {
    let frame = try frame(.binary(Data([1, 2, 3])), with: builder())

    #expect(frame.kind == .binary)
    #expect(frame.payload?.data == Data([1, 2, 3]))
}

@Test func compressedBinaryFrameShowsDecompressed() throws {
    let plain = Data(#"{"price":42}"#.utf8)

    let frame = try frame(.binary(try Fixtures.gzip(plain)), with: builder())

    #expect(frame.payload?.data == plain)
    #expect(frame.payload?.compression == .gzip)
    #expect(frame.payload?.isDecompressed == true)
}

@Test func frameOverTheCapIsTruncatedAndKeepsItsFullSize() throws {
    let frame = try frame(.binary(Data(count: 50)), with: builder(limit: 10))

    #expect(frame.byteCount == 50)
    guard case .truncated(let kept) = frame.payload?.content else {
        Issue.record("expected a truncated payload")
        return
    }
    #expect(kept.count == 10)
}

@Test func unparseableJSONFrameIsWithheldWhenJSONKeysAreConfigured() throws {
    let frame = try frame(.text(#"{"token":"#), with: builder(jsonKeys: ["token"]))

    #expect(frame.payload?.content == .withheld)
}

@Test func configuredJSONKeysAreRedactedInFrames() throws {
    let frame = try frame(.text(#"{"token":"secret"}"#), with: builder(jsonKeys: ["token"]))

    let text = try #require(frame.payload?.data.flatMap { String(data: $0, encoding: .utf8) })
    #expect(!text.contains("secret"))
    #expect(text.contains(Redactor.marker))
}

@Test func emptyFrameHasNoPayload() throws {
    let frame = try frame(.text(""), with: builder())

    #expect(frame.payload == nil)
    #expect(frame.byteCount == 0)
}

@Test func eventsPassThroughWithTheirDate() {
    let date = Date(timeIntervalSince1970: 9)
    let activity = RawSocketActivity(socket: socket, content: .event(.ping), date: date)

    #expect(builder().item(from: activity) == .event(.ping, date: date))
}
