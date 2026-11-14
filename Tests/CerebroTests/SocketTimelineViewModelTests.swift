import Foundation
import Testing
@testable import Cerebro

private let date = Date(timeIntervalSince1970: 0)

private func frame(
    _ direction: SocketDirection = .received,
    kind: SocketFrame.Kind = .text,
    payload: CapturedBody?
) -> SocketTimelineItem {
    .frame(
        SocketFrame(direction: direction, kind: kind, byteCount: payload?.byteCount ?? 0, date: date, payload: payload))
}

private func text(_ string: String) -> CapturedBody {
    CapturedBody(content: .complete(Data(string.utf8)), byteCount: string.utf8.count)
}

@MainActor
private func model(_ items: [SocketTimelineItem], name: String = "wss://example.com/feed") -> SocketTimelineViewModel {
    SocketTimelineViewModel(
        store: SocketStore(frameLimit: 10, payloadByteLimit: 100),
        connection: SocketConnection(source: .webSocketTask, name: name, startDate: date, timeline: items)
    )
}

@MainActor
private func frameRow(_ item: SocketTimelineItem) throws -> SocketFrameRow {
    guard case .frame(let row) = model([item]).row(at: 0) else {
        Issue.record("expected a frame row")
        throw CancellationError()
    }
    return row
}

@MainActor
private func eventText(_ event: SocketEvent) throws -> String {
    guard case .event(let text) = model([.event(event, date: date)]).row(at: 0) else {
        Issue.record("expected an event row")
        throw CancellationError()
    }
    return text
}

@Test @MainActor func titleIsTheHostWhenThereIsOne() {
    #expect(model([]).title == "example.com")
    #expect(model([], name: "Starscream sample").title == "Starscream sample")
}

@Test @MainActor func sentAndReceivedFramesAreToldApart() throws {
    #expect(try frameRow(frame(.sent, payload: text("a"))).isSent)
    #expect(try !frameRow(frame(.received, payload: text("a"))).isSent)
}

@Test @MainActor func frameShowsItsPayloadTypeAndSize() throws {
    let row = try frameRow(frame(kind: .text, payload: text("hello")))

    #expect(row.text == "hello")
    #expect(row.detail.hasPrefix("Text · 5 bytes ·"))
    #expect(row.body == text("hello"))
}

@Test @MainActor func binaryFrameShowsAsHex() throws {
    let payload = CapturedBody(content: .complete(Data([0, 255])), byteCount: 2)

    let row = try frameRow(frame(kind: .binary, payload: payload))

    #expect(row.text == "00ff")
    #expect(row.detail.hasPrefix("Binary ·"))
    #expect(row.body == payload)
}

@Test @MainActor func truncatedFrameSaysSo() throws {
    let payload = CapturedBody(content: .truncated(Data("abc".utf8)), byteCount: 9_000)

    let row = try frameRow(frame(payload: payload))

    #expect(row.text == "abc")
    #expect(row.detail.contains("truncated"))
}

@Test @MainActor func frameCompressionIsNamed() throws {
    let payload = CapturedBody(
        content: .complete(Data("abc".utf8)), byteCount: 3, compression: .gzip, isDecompressed: true)

    #expect(try frameRow(frame(payload: payload)).detail.contains("gzip"))
}

@Test @MainActor func withheldFrameSaysWhyAndDoesntOpen() throws {
    let row = try frameRow(frame(payload: CapturedBody(content: .withheld, byteCount: 9)))

    #expect(row.text.contains("Withheld"))
    #expect(row.body == nil)
}

@Test @MainActor func aFailedSendIsMarked() throws {
    let failed = SocketTimelineItem.frame(
        SocketFrame(direction: .sent, kind: .text, byteCount: 1, date: date, payload: text("x"), didFail: true)
    )

    let row = try frameRow(failed)

    #expect(row.didFail)
    #expect(row.detail.contains("failed"))
}

@Test @MainActor func aFrameTheBacklogDroppedSaysWhy() throws {
    let row = try frameRow(frame(payload: CapturedBody(content: .notStored, byteCount: 9)))

    #expect(row.text.contains("too fast"))
    #expect(row.body == nil)
}

@Test @MainActor func emptyFrameIsNamed() throws {
    let row = try frameRow(frame(payload: nil))

    #expect(row.text == "Empty frame")
    #expect(row.body == nil)
}

@Test @MainActor func eventsAreDescribed() throws {
    #expect(try eventText(.opened).hasPrefix("Opened ·"))
    #expect(try eventText(.ping).hasPrefix("Ping ·"))
    #expect(try eventText(.pong).hasPrefix("Pong ·"))
    #expect(try eventText(.stateChanged("Preparing")).hasPrefix("Preparing ·"))
    #expect(try eventText(.failed("broke")).hasPrefix("Failed: broke ·"))
}

@Test @MainActor func closeShowsWhateverItHas() throws {
    #expect(try eventText(.closed(code: 4001, reason: "bye")).hasPrefix("Closed: 4001 bye ·"))
    #expect(try eventText(.closed(code: 1000, reason: nil)).hasPrefix("Closed: 1000 ·"))
    #expect(try eventText(.closed(code: nil, reason: nil)).hasPrefix("Closed ·"))
}

@Test @MainActor func updatesOnlyFollowItsOwnSocket() {
    let mine = SocketConnection(source: .external, name: "mine", startDate: date)
    let model = SocketTimelineViewModel(
        store: SocketStore(frameLimit: 10, payloadByteLimit: 100),
        connection: mine
    )
    var changes = 0
    model.onChange = { changes += 1 }

    model.show([
        SocketConnection(source: .external, name: "other", startDate: date, timeline: [.event(.ping, date: date)])
    ])
    #expect(model.items.isEmpty)
    #expect(changes == 0)

    model.show([
        SocketConnection(
            id: mine.id, source: .external, name: "mine", startDate: date, timeline: [.event(.ping, date: date)])
    ])
    #expect(model.items.count == 1)
    #expect(changes == 1)

    model.show([SocketConnection(id: mine.id, source: .external, name: "mine", startDate: date, timeline: model.items)])
    #expect(changes == 1)
}

@Test func timeUsesA24HourClockToTheMillisecond() throws {
    let afternoon = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 17, minute: 8, second: 3))
    )

    #expect(DisplayFormat.time(afternoon) == "17:08:03.000")
}

@Test func shortBytesThatArentTextHaveNoPreview() {
    #expect(DisplayFormat.preview(of: Data([0xFF])) == nil)
    #expect(DisplayFormat.preview(of: Data([0xFF, 0xFE])) == nil)
    #expect(DisplayFormat.preview(of: Data([0x81, 0x7E, 0xFF])) == nil)
}

@Test func aCharacterCutOffAtThePreviewLimitIsDropped() {
    let text = String(repeating: "a", count: 399) + "é" + "b"

    #expect(DisplayFormat.preview(of: Data(text.utf8)) == String(repeating: "a", count: 399))
}
