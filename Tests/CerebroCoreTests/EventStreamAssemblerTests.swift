import Foundation
import Testing
@testable import CerebroCore

private func assembler(limit: Int = 100_000, jsonKeys: Set<String> = []) -> EventStreamAssembler {
    let redactor = Redactor(rules: RedactionRules(jsonKeys: jsonKeys))
    return EventStreamAssembler(
        processor: BodyProcessor(limit: limit, decoders: [], redactor: redactor),
        url: URL(string: "https://example.com/feed"),
        method: "GET",
        openedAt: Date(timeIntervalSince1970: 0)
    )
}

private func text(of event: CapturedSSEEvent?) -> String? {
    event?.data.data.flatMap { String(data: $0, encoding: .utf8) }
}

@Suite struct EventStreamAssemblerTests {
    @Test func eventsAreKeptInOrderWithTheTimeTheyArrived() {
        var assembler = assembler()
        let later = Date(timeIntervalSince1970: 9)

        let didChange = assembler.receive(Data("id: 4\nevent: tick\ndata: one\n\ndata: two\n\n".utf8), at: later)

        #expect(didChange)

        let stream = assembler.stream(.open)
        #expect(stream.state == .open)
        #expect(stream.eventCount == 2)
        #expect(stream.events.map(text) == ["one", "two"])
        #expect(stream.events.map(\.type) == ["tick", "message"])
        #expect(stream.events.map(\.id) == ["4", "4"])
        #expect(stream.events.map(\.date) == [later, later])
        #expect(!stream.isTruncated)
        #expect(assembler.lastReceived == later)
    }

    @Test func bytesThatCompleteNoEventChangeNothingButTheTime() {
        var assembler = assembler()
        let later = Date(timeIntervalSince1970: 9)

        let didChange = assembler.receive(Data(": keep-alive\n\ndata: half".utf8), at: later)

        #expect(!didChange)

        #expect(assembler.stream(.open).eventCount == 0)
        #expect(assembler.lastReceived == later)
    }

    @Test func pastTheEventLimitTheOldestGoAndEveryEventIsCounted() {
        var assembler = assembler()
        let total = EventStreamAssembler.eventLimit + 5
        let feed = (0..<total).map { "data: \($0)\n\n" }.joined()

        _ = assembler.receive(Data(feed.utf8), at: Date())

        let stream = assembler.stream(.completed)
        #expect(stream.eventCount == total)
        #expect(stream.events.count == EventStreamAssembler.eventLimit)
        #expect(text(of: stream.events.first) == "5")
        #expect(text(of: stream.events.last) == String(total - 1))
        #expect(stream.isTruncated)
    }

    @Test func pastTheByteLimitTheOldestGoAndEveryEventIsCounted() {
        var assembler = assembler(limit: 100)
        let feed = (0..<10).map { "data: \($0)\(String(repeating: "x", count: 29))\n\n" }.joined()

        // One event at a time, as a server sends them, so nothing waits in the parser.
        for piece in feed.components(separatedBy: "\n\n") where !piece.isEmpty {
            _ = assembler.receive(Data((piece + "\n\n").utf8), at: Date())
        }

        let stream = assembler.stream(.open)
        #expect(stream.eventCount == 10)
        #expect(stream.events.count == 2)
        #expect(text(of: stream.events.last)?.hasPrefix("9") == true)
        #expect(stream.isTruncated)
    }

    @Test func losingFramingKeepsWhatArrivedAndMarksTheStream() {
        var assembler = assembler()
        _ = assembler.receive(Data("data: kept\n\n".utf8), at: Date())

        assembler.loseFraming()
        let didChange = assembler.receive(Data("data: lost\n\n".utf8), at: Date())

        #expect(!didChange)
        let stream = assembler.stream(.open)
        #expect(stream.events.map(text) == ["kept"])
        #expect(stream.isTruncated)
    }

    @Test func anEventTooLargeToParseStopsTheStreamAndSaysSoOnce() {
        var assembler = assembler(limit: 16)

        let first = assembler.receive(Data("data: \(String(repeating: "x", count: 64))".utf8), at: Date())
        let second = assembler.receive(Data("\n\n".utf8), at: Date())

        #expect(first)
        #expect(!second)

        #expect(assembler.stream(.open).isTruncated)
        #expect(assembler.stream(.open).eventCount == 0)
    }

    @Test func configuredKeysAreRedactedInJSONData() throws {
        var assembler = assembler(jsonKeys: ["token"])

        _ = assembler.receive(Data(#"data: {"token":"s3cret","user":"ada"}"#.utf8) + Data("\n\n".utf8), at: Date())

        let stored = try #require(text(of: assembler.stream(.open).events.first))
        #expect(!stored.contains("s3cret"))
        #expect(stored.contains(Redactor.marker))
        #expect(stored.contains("ada"))
    }

    @Test func dataThatCannotBeRedactedIsWithheld() {
        var assembler = assembler(jsonKeys: ["token"])

        // `[DONE]` starts like JSON but doesn't parse, and the second names a key in plain text.
        _ = assembler.receive(Data("data: [DONE]\n\ndata: token=s3cret\n\ndata: plain\n\n".utf8), at: Date())

        let events = assembler.stream(.open).events
        #expect(events.map(\.data.content) == [.withheld, .withheld, .complete(Data("plain".utf8))])
        #expect(events.map(\.data.byteCount) == [6, 12, 5])
    }

    @Test func doneIsKeptWhenNoKeysAreConfigured() {
        var assembler = assembler()

        _ = assembler.receive(Data("data: [DONE]\n\n".utf8), at: Date())

        #expect(text(of: assembler.stream(.open).events.first) == "[DONE]")
    }

    @Test func anIDOrTypeNamingAKeyIsRedacted() {
        var assembler = assembler(jsonKeys: ["token"])

        _ = assembler.receive(
            Data("id: token-abc\nevent: Token_refresh\ndata: x\n\nevent: tick\ndata: y\n\n".utf8), at: Date())

        let events = assembler.stream(.open).events
        #expect(events.map(\.id) == [Redactor.marker, Redactor.marker])
        #expect(events.map(\.type) == [Redactor.marker, "tick"])
    }

    @Test func emptyDataIsAnEmptyBody() {
        var assembler = assembler()

        _ = assembler.receive(Data("data\n\n".utf8), at: Date())

        #expect(assembler.stream(.open).events.first?.data.content == .complete(Data()))
    }
}
