import Foundation
import Testing
@testable import Cerebro

@MainActor
private func section(_ title: String, in model: LogInspectorViewModel) -> InspectorSection? {
    model.sections.first { $0.title == title }
}

private func value(_ title: String, in section: InspectorSection?) -> String? {
    section?.rows.first { $0.title == title }?.value
}

private let full = HTTPTransaction(
    request: CapturedRequest(
        url: URL(string: "https://example.com/quotes?symbol=TICK"),
        method: "GET",
        headers: [NamedValue(name: "Accept", value: "application/json")],
        queryParameters: [NamedValue(name: "symbol", value: "TICK")],
        startDate: Date(timeIntervalSince1970: 0)
    ),
    response: CapturedResponse(
        statusCode: 200,
        headers: [NamedValue(name: "Server", value: "test")],
        body: CapturedBody(content: .complete(Data("{}".utf8)), byteCount: 2),
        mimeType: "application/json",
        contentEncoding: "gzip",
        endDate: Date(timeIntervalSince1970: 1)
    ),
    timing: TransactionTiming(dns: 0.01, tls: nil, firstByte: 0.05, total: 1.5),
    connection: ConnectionDetails(
        remoteAddress: "1.2.3.4",
        remotePort: 443,
        httpVersion: "h2",
        tlsVersion: "TLS 1.3",
        isReused: true
    ),
    size: TransferSize(bytesSent: 100, bytesReceived: 300, wireBodyBytes: 200, decodedBodyBytes: 1_000)
)

private func withBody(_ body: CapturedBody?) -> HTTPTransaction {
    HTTPTransaction(
        request: CapturedRequest(url: nil, method: "POST", body: body, startDate: Date(timeIntervalSince1970: 0))
    )
}

@Test @MainActor func showsEverySectionInOrder() {
    let model = LogInspectorViewModel(transaction: full)

    #expect(
        model.sections.map(\.title) == [
            "Overview", "Request headers", "Query parameters", "Response headers", "Response body", "Timing", "Size",
            "Connection",
        ]
    )
    #expect(model.title == "quotes")
}

@Test @MainActor func overviewAndConnectionCarryTheirFields() {
    let model = LogInspectorViewModel(transaction: full)

    #expect(value("URL", in: section("Overview", in: model)) == "https://example.com/quotes?symbol=TICK")
    #expect(value("Status", in: section("Overview", in: model)) == "200")
    #expect(value("Remote", in: section("Connection", in: model)) == "1.2.3.4:443")
    #expect(value("Reused connection", in: section("Connection", in: model)) == "Yes")
    #expect(value("TLS version", in: section("Connection", in: model)) == "TLS 1.3")
}

@Test @MainActor func timingLeavesOutStagesThatDidntHappen() {
    let timing = section("Timing", in: LogInspectorViewModel(transaction: full))

    #expect(timing?.rows.map(\.title) == ["DNS", "First byte", "Total"])
    #expect(value("DNS", in: timing) == "10 ms")
    #expect(value("Total", in: timing) == "1.50 s")
}

@Test @MainActor func sizeShowsTheEncodingAndRatio() {
    let size = section("Size", in: LogInspectorViewModel(transaction: full))

    #expect(value("Encoding", in: size) == "gzip")
    #expect(value("Compression ratio", in: size) == "5.0x")
}

@Test @MainActor func failureShowsItsError() {
    let failed = HTTPTransaction(
        request: CapturedRequest(url: nil, method: "GET", startDate: Date(timeIntervalSince1970: 0)),
        failure: CapturedFailure(domain: "Domain", code: 7, description: "broke")
    )

    #expect(
        value("Error", in: section("Overview", in: LogInspectorViewModel(transaction: failed))) == "broke (Domain 7)")
}

@Test @MainActor func completeBodyOpens() throws {
    let body = CapturedBody(content: .complete(Data("{}".utf8)), byteCount: 2)

    let row = try #require(section("Request body", in: LogInspectorViewModel(transaction: withBody(body)))?.rows.first)

    #expect(row.body == body)
    #expect(row.title == "View body")
}

@Test @MainActor func truncatedBodyOpensAndSaysSo() throws {
    let body = CapturedBody(content: .truncated(Data("{".utf8)), byteCount: 5_000_000)

    let row = try #require(section("Request body", in: LogInspectorViewModel(transaction: withBody(body)))?.rows.first)

    #expect(row.body == body)
    #expect(row.title.contains("truncated"))
    #expect(row.value.contains("5"))
}

@Test @MainActor func withheldBodyShowsItsMarkerAndDoesntOpen() throws {
    let body = CapturedBody(content: .withheld, byteCount: 10)

    let row = try #require(section("Request body", in: LogInspectorViewModel(transaction: withBody(body)))?.rows.first)

    #expect(row.body == nil)
    #expect(row.title.contains("Withheld"))
}

@Test @MainActor func downloadBodySaysItWasNotStored() throws {
    let body = CapturedBody(content: .notStored, byteCount: 10)

    let row = try #require(section("Request body", in: LogInspectorViewModel(transaction: withBody(body)))?.rows.first)

    #expect(row.body == nil)
    #expect(row.title.contains("Not stored"))
}

@Test @MainActor func compressionIsNamed() throws {
    let shownRaw = CapturedBody(content: .complete(Data([1])), byteCount: 1, compression: .zstd)
    let decompressed = CapturedBody(
        content: .complete(Data([1])), byteCount: 1, compression: .gzip, isDecompressed: true)

    let raw = try #require(
        section("Request body", in: LogInspectorViewModel(transaction: withBody(shownRaw)))?.rows.first)
    let read = try #require(
        section("Request body", in: LogInspectorViewModel(transaction: withBody(decompressed)))?.rows.first)

    #expect(raw.title.contains("zstd, shown raw"))
    #expect(read.title.contains("gzip, decompressed for display"))
}
