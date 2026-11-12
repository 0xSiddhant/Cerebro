import Foundation
import Testing
@testable import CerebroCore

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var all: [String] {
        lock.withLock { stored }
    }

    func add(_ line: String) {
        lock.withLock { stored.append(line) }
    }
}

private func logged(_ transaction: HTTPTransaction, level: ConsoleLevel) -> [String] {
    let lines = Lines()
    ConsoleLogger(level: level) { lines.add($0) }.log(transaction)
    return lines.all
}

private let transaction = HTTPTransaction(
    request: CapturedRequest(
        url: URL(string: "https://example.com/a"),
        method: "POST",
        headers: [NamedValue(name: "Authorization", value: Redactor.marker)],
        body: CapturedBody(content: .complete(Data(#"{"a":1}"#.utf8)), byteCount: 7),
        startDate: Date(timeIntervalSince1970: 0)
    ),
    response: CapturedResponse(
        statusCode: 201,
        headers: [NamedValue(name: "Server", value: "test")],
        body: CapturedBody(content: .withheld, byteCount: 9),
        endDate: Date(timeIntervalSince1970: 1)
    ),
    timing: TransactionTiming(total: 0.25)
)

@Test func offPrintsNothing() {
    #expect(logged(transaction, level: .off).isEmpty)
}

@Test func summaryPrintsOneLine() {
    #expect(logged(transaction, level: .summary) == ["[Cerebro] POST https://example.com/a 201 250 ms"])
}

@Test func fullAddsHeadersAndBodies() throws {
    let lines = logged(transaction, level: .full)

    #expect(lines.count == 2)
    let details = try #require(lines.last)
    #expect(details.contains("Authorization: \(Redactor.marker)"))
    #expect(details.contains("\"a\" : 1"))
    #expect(details.contains("Server: test"))
    #expect(details.contains("withheld"))
}

@Test func summaryDescribesAFailure() {
    let failed = HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com"), method: "GET", startDate: Date()),
        failure: CapturedFailure(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, description: "timed out")
    )

    #expect(logged(failed, level: .summary).first?.contains("failed: timed out") == true)
}

@Test func summaryDescribesACancellation() {
    let cancelled = HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com"), method: "GET", startDate: Date()),
        failure: CapturedFailure(domain: NSURLErrorDomain, code: NSURLErrorCancelled, description: "cancelled")
    )

    #expect(logged(cancelled, level: .summary).first?.contains("cancelled") == true)
}

private func fullLog(of body: CapturedBody) -> String {
    let request = CapturedRequest(url: URL(string: "https://a.com"), method: "POST", body: body, startDate: Date())
    return logged(HTTPTransaction(request: request), level: .full).joined(separator: "\n")
}

@Test func decodedProtobufPrintsAsPrettyJSONAtFull() {
    let body = CapturedBody(content: .complete(Data(#"{"a":1}"#.utf8)), byteCount: 2, isDecoded: true)

    #expect(fullLog(of: body).contains("{\n  \"a\" : 1\n}"))
}

@Test func protobufWithNoRulePrintsAsHexAtFull() {
    let body = CapturedBody(content: .complete(Data("123".utf8)), byteCount: 3, undecoded: .noRule)

    #expect(fullLog(of: body).contains("313233"))
}

@Test func truncatedProtobufPrintsAsHexAtFull() {
    let body = CapturedBody(content: .truncated(Data("123".utf8)), byteCount: 500, undecoded: .truncated)

    let log = fullLog(of: body)

    #expect(log.contains("truncated"))
    #expect(log.contains("313233"))
}

private let finishedStream = Fixtures.stream(
    .completed,
    events: [
        Fixtures.event(#"{"n":1}"#, id: "7", type: "tick"),
        CapturedSSEEvent(data: CapturedBody(content: .withheld, byteCount: 6), date: Date()),
    ]
)

@Test func summaryOfAStreamIsOneLineWithoutItsEvents() {
    let lines = logged(finishedStream, level: .summary)

    #expect(lines.count == 1)
    #expect(lines.first?.contains("tick") == false)
}

@Test func fullListsAStreamsEvents() throws {
    let details = try #require(logged(finishedStream, level: .full).last)

    #expect(details.contains("Events (2):"))
    #expect(details.contains(#"tick #7: {"n":1}"#))
    #expect(details.contains("message: withheld"))
}

@Test func fullSaysWhenOnlyTheNewestEventsWereKept() throws {
    let stream = CapturedEventStream(
        state: .completed, eventCount: 50, events: [Fixtures.event("last")], isTruncated: true)
    let transaction = HTTPTransaction(
        request: CapturedRequest(url: nil, method: "GET", startDate: Date()), eventStream: stream)

    #expect(logged(transaction, level: .full).last?.contains("Events (newest 1 of 50):") == true)
}
