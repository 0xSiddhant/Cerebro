import Foundation
import Testing
@testable import Cerebro

@MainActor
private func section(_ title: String, of tab: InspectorTab, in model: LogInspectorViewModel) -> InspectorSection? {
    model.sections(for: tab).first { $0.title == title }
}

private func value(_ title: String, in section: InspectorSection?) -> String? {
    section?.rows.first { $0.title == title }?.value
}

@MainActor
private func requestBodyRow(_ body: CapturedBody) throws -> InspectorRow {
    let model = LogInspectorViewModel(transaction: withBody(body))
    return try #require(section("Body", of: .request, in: model)?.rows.first)
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

@Test @MainActor func eachPageShowsItsSectionsInOrder() {
    let model = LogInspectorViewModel(transaction: full)

    #expect(model.sections(for: .response).map(\.title) == ["Body", "Headers"])
    #expect(model.sections(for: .request).map(\.title) == ["General", "Query", "Headers"])
    #expect(model.sections(for: .metrics).map(\.title) == ["Timing", "Size", "Connection"])
    #expect(model.title == "quotes")
}

@Test @MainActor func summaryCarriesTheHeadlineFigures() {
    let summary = LogInspectorViewModel(transaction: full).summary

    #expect(summary.method == "GET")
    #expect(summary.url == "https://example.com/quotes?symbol=TICK")
    #expect(summary.status == "200")
    #expect(summary.outcome == .success)
    #expect(summary.error == nil)
    #expect(
        summary.stats == [
            InspectorStat(title: "Time", value: "1.50 s"),
            InspectorStat(title: "Size", value: DisplayFormat.bytes(300)),
            InspectorStat(title: "Type", value: "json"),
            InspectorStat(title: "Protocol", value: "h2"),
        ]
    )
}

@Test @MainActor func connectionCarriesItsFields() {
    let connection = section("Connection", of: .metrics, in: LogInspectorViewModel(transaction: full))

    #expect(value("Remote", in: connection) == "1.2.3.4:443")
    #expect(value("Reused connection", in: connection) == "Yes")
    #expect(value("TLS version", in: connection) == "TLS 1.3")
    #expect(value("Network", in: connection) == "Not cellular")
}

@Test @MainActor func networkNamesEveryTraitThatApplies() {
    let transaction = HTTPTransaction(
        request: CapturedRequest(url: nil, method: "GET", startDate: Date(timeIntervalSince1970: 0)),
        connection: ConnectionDetails(isCellular: true, isExpensive: true, isConstrained: true)
    )

    let connection = section("Connection", of: .metrics, in: LogInspectorViewModel(transaction: transaction))

    #expect(value("Network", in: connection) == "Cellular, Expensive, Low Data Mode")
}

@Test @MainActor func timingLeavesOutStagesThatDidntHappen() {
    let timing = section("Timing", of: .metrics, in: LogInspectorViewModel(transaction: full))

    #expect(timing?.rows.map(\.title) == ["DNS", "First byte", "Total"])
    #expect(value("DNS", in: timing) == "10 ms")
    #expect(value("Total", in: timing) == "1.50 s")
}

@Test @MainActor func timingBarsStayInsideTheRequest() throws {
    let transaction = HTTPTransaction(
        request: CapturedRequest(url: nil, method: "GET", startDate: Date(timeIntervalSince1970: 0)),
        timing: TransactionTiming(dns: 1, connect: 1, firstByte: 9, total: 4)
    )

    let rows = try #require(section("Timing", of: .metrics, in: LogInspectorViewModel(transaction: transaction))?.rows)

    #expect(rows.first { $0.title == "Connect" }?.span == InspectorSpan(start: 0.25, length: 0.25))
    #expect(rows.first { $0.title == "First byte" }?.span == InspectorSpan(start: 0.5, length: 0.5))
    #expect(rows.first { $0.title == "Total" }?.span == InspectorSpan(start: 0, length: 1))
}

@Test @MainActor func sizeShowsTheEncodingAndRatio() {
    let size = section("Size", of: .metrics, in: LogInspectorViewModel(transaction: full))

    #expect(value("Encoding", in: size) == "gzip")
    #expect(value("Compression ratio", in: size) == "5.0x")
}

@Test @MainActor func failureShowsItsErrorInTheSummaryAndTheResponsePage() {
    let failed = HTTPTransaction(
        request: CapturedRequest(url: nil, method: "GET", startDate: Date(timeIntervalSince1970: 0)),
        failure: CapturedFailure(domain: "Domain", code: 7, description: "broke")
    )

    let model = LogInspectorViewModel(transaction: failed)

    #expect(model.summary.error == "broke")
    #expect(model.summary.status == "Failed")
    let error = section("Error", of: .response, in: model)
    #expect(value("Description", in: error) == "broke")
    #expect(value("Domain", in: error) == "Domain")
    #expect(value("Code", in: error) == "7")
}

@Test @MainActor func pageWithNothingSaysSoInsteadOfStayingBlank() {
    let bare = HTTPTransaction(
        request: CapturedRequest(url: nil, method: "GET", startDate: Date(timeIntervalSince1970: 0))
    )

    #expect(
        LogInspectorViewModel(transaction: bare).sections(for: .metrics).first?.rows.first?.title == "Nothing captured")
}

@Test @MainActor func completeBodyOpensAndPreviewsItsStart() throws {
    let body = CapturedBody(content: .complete(Data("{\"a\":1}".utf8)), byteCount: 7)

    let row = try requestBodyRow(body)

    #expect(row.body == body)
    #expect(row.title == "View body")
    #expect(row.isBodyRow)
    #expect(row.preview == "{\"a\":1}")
}

@Test @MainActor func previewStopsAtItsLimitWithoutBreakingACharacter() throws {
    let text = String(repeating: "a", count: 399) + "é" + String(repeating: "b", count: 100)
    let body = CapturedBody(content: .complete(Data(text.utf8)), byteCount: text.utf8.count)

    let preview = try #require(try requestBodyRow(body).preview)

    #expect(preview.hasPrefix(String(repeating: "a", count: 399)))
    #expect(preview.utf8.count <= 403)
}

@Test @MainActor func binaryBodyPreviewsAsHex() throws {
    let body = CapturedBody(content: .complete(Data([0xFF, 0x00, 0xFE, 0x01])), byteCount: 4)

    #expect(try requestBodyRow(body).preview == "ff00fe01")
}

@Test @MainActor func protobufWithNoRuleSaysSoAndPreviewsAsHexEvenWhenItPassesForText() throws {
    let body = CapturedBody(content: .complete(Data("abc".utf8)), byteCount: 3, undecoded: .noRule)

    let row = try requestBodyRow(body)

    #expect(row.title.contains("proto, no rule"))
    #expect(row.preview == "616263")
}

@Test @MainActor func protobufOverTheCapSaysSoAndStillOpens() throws {
    let body = CapturedBody(content: .truncated(Data([0x0A, 0x01])), byteCount: 500, undecoded: .truncated)

    let row = try requestBodyRow(body)

    #expect(row.title.contains("truncated"))
    #expect(row.title.contains("too large to decode"))
    #expect(row.body == body)
}

@Test @MainActor func protobufThatWontDecodeSaysSo() throws {
    let body = CapturedBody(content: .complete(Data([0xFF])), byteCount: 1, undecoded: .failed)

    #expect(try requestBodyRow(body).title.contains("couldn't be decoded"))
}

@Test @MainActor func aDecodedBodySaysSoAndPreviewsItsJSON() throws {
    let body = CapturedBody(content: .complete(Data(#"{"a":1}"#.utf8)), byteCount: 9, isDecoded: true)

    let row = try requestBodyRow(body)

    #expect(row.title.contains("decoded"))
    #expect(row.preview == #"{"a":1}"#)
}

@Test @MainActor func truncatedBodyOpensAndSaysSo() throws {
    let body = CapturedBody(content: .truncated(Data("{".utf8)), byteCount: 5_000_000)

    let row = try requestBodyRow(body)

    #expect(row.body == body)
    #expect(row.title.contains("truncated"))
    #expect(row.value.contains("5"))
}

@Test @MainActor func withheldBodyShowsItsMarkerAndDoesntOpen() throws {
    let row = try requestBodyRow(CapturedBody(content: .withheld, byteCount: 10))

    #expect(row.body == nil)
    #expect(row.isBodyRow)
    #expect(row.title.contains("Withheld"))
}

@Test @MainActor func downloadBodySaysItWasNotStored() throws {
    let row = try requestBodyRow(CapturedBody(content: .notStored, byteCount: 10))

    #expect(row.body == nil)
    #expect(row.title.contains("Not stored"))
}

@Test @MainActor func compressionIsNamed() throws {
    let raw = try requestBodyRow(CapturedBody(content: .complete(Data([1])), byteCount: 1, compression: .zstd))
    let read = try requestBodyRow(
        CapturedBody(content: .complete(Data([1])), byteCount: 1, compression: .gzip, isDecompressed: true)
    )

    #expect(raw.title.contains("zstd, shown raw"))
    #expect(read.title.contains("gzip, decompressed for display"))
}

// MARK: - Event streams

private func event(_ text: String, id: String? = nil, type: String = "message") -> CapturedSSEEvent {
    CapturedSSEEvent(
        id: id,
        type: type,
        data: CapturedBody(content: .complete(Data(text.utf8)), byteCount: text.utf8.count),
        date: Date(timeIntervalSince1970: 2)
    )
}

private func stream(
    id: UUID = UUID(),
    _ state: CapturedEventStream.State,
    events: [CapturedSSEEvent],
    eventCount: Int? = nil,
    isTruncated: Bool = false
) -> HTTPTransaction {
    HTTPTransaction(
        id: id,
        request: CapturedRequest(
            url: URL(string: "https://example.com/feed"), method: "GET", startDate: Date(timeIntervalSince1970: 0)),
        response: CapturedResponse(
            statusCode: 200,
            headers: [NamedValue(name: "Content-Type", value: "text/event-stream")],
            mimeType: "text/event-stream",
            endDate: Date(timeIntervalSince1970: 1)
        ),
        eventStream: CapturedEventStream(
            state: state, eventCount: eventCount ?? events.count, events: events, isTruncated: isTruncated)
    )
}

@Test @MainActor func eventsAreTheLastSectionOfTheResponsePage() throws {
    let model = LogInspectorViewModel(
        transaction: stream(.open, events: [event("one", id: "7", type: "tick"), event("two")]))

    #expect(model.sections(for: .response).map(\.title) == ["Headers", "Events"])
    let rows = try #require(model.sections(for: .response).last?.rows)
    #expect(rows.count == 2)
    #expect(rows[0].title.hasPrefix("tick · #7 · "))
    #expect(rows[1].title.hasPrefix("message · "))
    #expect(rows[0].preview == "one")
    #expect(rows[0].body?.data == Data("one".utf8))
    #expect(rows[0].bodyTitle == "Event data")
    #expect(rows.map(\.isBodyRow) == [true, true])
}

@Test @MainActor func aStreamsSummarySaysWhetherItIsLiveAndCountsItsEvents() {
    let live = LogInspectorViewModel(transaction: stream(.open, events: [event("one")]))
    let ended = LogInspectorViewModel(transaction: stream(.completed, events: [event("one")], eventCount: 1_500))

    #expect(
        live.summary.stats == [
            InspectorStat(title: "Stream", value: "Live"), InspectorStat(title: "Events", value: "1"),
        ])
    #expect(ended.summary.stats.map(\.value) == ["Ended", "1,500"])
}

@Test @MainActor func aStreamWithNoEventsSaysSo() {
    let waiting = LogInspectorViewModel(transaction: stream(.open, events: []))
    let empty = LogInspectorViewModel(transaction: stream(.completed, events: []))

    #expect(waiting.sections(for: .response).last?.rows.map(\.title) == ["Waiting for events"])
    #expect(empty.sections(for: .response).last?.rows.map(\.title) == ["No events"])
}

@Test @MainActor func theEventsTitleSaysWhenSomeAreMissing() {
    let dropped = LogInspectorViewModel(
        transaction: stream(.open, events: [event("last")], eventCount: 1_200, isTruncated: true))
    let stopped = LogInspectorViewModel(transaction: stream(.open, events: [event("only")], isTruncated: true))

    #expect(dropped.sections(for: .response).last?.title == "Events · newest 1 of 1,200")
    #expect(stopped.sections(for: .response).last?.title == "Events · incomplete, they arrived too fast")
}

@Test @MainActor func withheldAndTruncatedEventDataIsLabelledAndOnlyStoredDataOpens() throws {
    let events = [
        CapturedSSEEvent(data: CapturedBody(content: .withheld, byteCount: 6), date: Date()),
        CapturedSSEEvent(data: CapturedBody(content: .truncated(Data("abc".utf8)), byteCount: 900), date: Date()),
        CapturedSSEEvent(data: CapturedBody(content: .complete(Data()), byteCount: 0), date: Date()),
    ]
    let model = LogInspectorViewModel(transaction: stream(.completed, events: events))

    let rows = try #require(model.sections(for: .response).last?.rows)
    #expect(rows[0].title.hasSuffix("withheld, because it couldn't be redacted"))
    #expect(rows[0].body == nil)
    #expect(rows[1].title.hasSuffix("truncated"))
    #expect(rows[1].body != nil)
    #expect(rows[2].body == nil)
}

@Test @MainActor func anOpenStreamFollowsTheStoreAndARequestWithoutAStreamHasNoEvents() {
    let open = stream(.open, events: [event("one")])
    let model = LogInspectorViewModel(transaction: open)
    var changes = 0
    model.onChange = { changes += 1 }

    let finished = stream(id: open.id, .completed, events: [event("one"), event("two")])
    model.show([full, finished])
    #expect(changes == 1)
    #expect(model.transaction == finished)
    #expect(model.sections(for: .response).last?.rows.count == 2)
    #expect(model.summary.stats.first?.value == "Ended")

    // The same again, or a store that no longer holds it, changes nothing.
    model.show([full, finished])
    model.show([full])
    #expect(changes == 1)
    #expect(model.transaction == finished)

    #expect(LogInspectorViewModel(transaction: full).sections(for: .response).map(\.title) == ["Body", "Headers"])
}
