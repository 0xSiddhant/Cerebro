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
