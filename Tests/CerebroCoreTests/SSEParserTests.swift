import Foundation
import Testing
@testable import CerebroCore

private typealias Event = SSEParser.Event

/// Parses `text` in one piece.
private func events(in text: String, limit: Int = 10_000) -> [Event] {
    var parser = SSEParser(limit: limit)
    return parser.parse(Data(text.utf8))
}

private func event(_ data: String, id: String? = nil, type: String = "message") -> Event {
    Event(id: id, type: type, data: Data(data.utf8))
}

@Suite struct SSEParserTests {
    @Test func anEventEndsAtAnEmptyLine() {
        #expect(events(in: "data: one\n\ndata: two\n\n") == [event("one"), event("two")])
    }

    @Test(arguments: ["\n", "\r", "\r\n"])
    func everyLineEndingWorks(ending: String) {
        let text = ["event: tick", "id: 7", "data: one", "", ""].joined(separator: ending)

        #expect(events(in: text) == [event("one", id: "7", type: "tick")])
    }

    @Test func severalDataLinesJoinWithLineFeeds() {
        #expect(events(in: "data: one\ndata:\ndata: three\n\n") == [event("one\n\nthree")])
    }

    @Test func onlyOneSpaceAfterTheColonIsDropped() {
        #expect(events(in: "data:  two spaces\n\ndata:none\n\n") == [event(" two spaces"), event("none")])
    }

    @Test func commentsAndRetryAreNotEvents() {
        #expect(events(in: ": keep-alive\n\nretry: 3000\n\n: another\ndata: real\n\n") == [event("real")])
    }

    @Test func anEventWithoutDataIsIgnoredAndItsTypeDoesNotCarryOver() {
        #expect(events(in: "event: orphan\n\ndata: next\n\n") == [event("next")])
    }

    @Test func emptyDataStillCounts() {
        #expect(events(in: "data\n\ndata:\n\n") == [event(""), event("")])
    }

    @Test func theLastEventIDStaysInEffectUntilItIsReplaced() {
        let text = "id: 1\ndata: a\n\ndata: b\n\nid\ndata: c\n\n"

        #expect(events(in: text) == [event("a", id: "1"), event("b", id: "1"), event("c")])
    }

    @Test func anIDHoldingANullIsIgnored() {
        #expect(events(in: "id: 1\ndata: a\n\nid: bad\u{0}\ndata: b\n\n").map(\.id) == ["1", "1"])
    }

    @Test func aRepeatedFieldKeepsItsLastValueAndUnknownFieldsAreIgnored() {
        let text = "event: first\nevent: second\nid: 1\nid: 2\nfoo: bar\ndata: x\n\n"

        #expect(events(in: text) == [event("x", id: "2", type: "second")])
    }

    @Test func aLeadingByteOrderMarkIsDropped() {
        var parser = SSEParser(limit: 1_000)

        let parsed = parser.parse(Data([0xEF, 0xBB, 0xBF]) + Data("data: one\n\n".utf8))

        #expect(parsed == [event("one")])
    }

    @Test func anUnfinishedEventIsNeverReported() {
        #expect(events(in: "data: done\n\ndata: half").map(\.data) == [Data("done".utf8)])
    }

    /// Splits the stream after every possible byte, which covers a cut inside a CRLF, a field name,
    /// the byte order mark and a multi-byte character.
    @Test func wherePiecesEndNeverChangesTheResult() {
        let stream =
            Data([0xEF, 0xBB, 0xBF])
            + Data("id: 1\r\nevent: grüße\r\ndata: héllo 🌍\r\ndata: wörld\r\n\r\n: ping\r\rdata: two\r\r".utf8)
        let expected = [event("héllo 🌍\nwörld", id: "1", type: "grüße"), event("two", id: "1")]

        for cut in 0...stream.count {
            var parser = SSEParser(limit: 1_000)
            let parsed = parser.parse(stream.prefix(cut)) + parser.parse(stream.dropFirst(cut))
            #expect(parsed == expected, "split after byte \(cut)")
        }
        var parser = SSEParser(limit: 1_000)
        let byteByByte = stream.flatMap { parser.parse(Data([$0])) }
        #expect(byteByByte == expected)
    }

    @Test func aLineOverTheLimitStopsParsingForGood() {
        var parser = SSEParser(limit: 16)

        let before = parser.parse(Data("data: ok\n\n".utf8))
        let tooLong = parser.parse(Data("data: \(String(repeating: "x", count: 32))".utf8))
        let after = parser.parse(Data("\n\ndata: later\n\n".utf8))

        #expect(before == [event("ok")])
        #expect(tooLong.isEmpty)
        #expect(after.isEmpty)
        #expect(parser.hasLostFraming)
    }

    @Test func dataOverTheLimitAcrossLinesStopsParsing() {
        var parser = SSEParser(limit: 16)

        let parsed = parser.parse(Data("data: 12345678\ndata: 12345678\ndata: 12345678\n\n".utf8))

        #expect(parsed.isEmpty)
        #expect(parser.hasLostFraming)
    }
}
