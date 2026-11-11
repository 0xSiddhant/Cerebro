import Foundation
import Testing
@testable import CerebroCore

private func object(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

private func entries(_ transactions: [HTTPTransaction]) throws -> [[String: Any]] {
    let log = try #require(try object(TransactionExport.har(transactions))["log"] as? [String: Any])
    return try #require(log["entries"] as? [[String: Any]])
}

private func child(_ key: String, of parent: [String: Any]) throws -> [String: Any] {
    try #require(parent[key] as? [String: Any])
}

private let full = HTTPTransaction(
    request: CapturedRequest(
        url: URL(string: "https://example.com/orders?page=2"),
        method: "POST",
        headers: [NamedValue(name: "Content-Type", value: "application/json")],
        queryParameters: [NamedValue(name: "page", value: "2")],
        body: CapturedBody(content: .complete(Data(#"{"a":1}"#.utf8)), byteCount: 7, contentType: "application/json"),
        startDate: Date(timeIntervalSince1970: 1_700_000_000.25)
    ),
    response: CapturedResponse(
        statusCode: 201,
        headers: [NamedValue(name: "Location", value: "/orders/9")],
        body: CapturedBody(content: .complete(Data("ok".utf8)), byteCount: 2),
        mimeType: "text/plain",
        endDate: Date(timeIntervalSince1970: 1_700_000_001)
    ),
    timing: TransactionTiming(dns: 0.01, connect: 0.05, tls: 0.03, requestSent: 0.002, firstByte: 0.1, total: 0.5),
    connection: ConnectionDetails(remoteAddress: "1.2.3.4", remotePort: 443, httpVersion: "h2"),
    size: TransferSize(bytesSent: 200, bytesReceived: 300, wireBodyBytes: 2, decodedBodyBytes: 2)
)

@Test func harHasTheShapeToolsExpect() throws {
    let log = try child("log", of: try object(TransactionExport.har([full])))

    #expect(log["version"] as? String == "1.2")
    #expect(try child("creator", of: log)["name"] as? String == "Cerebro")
    #expect((log["entries"] as? [Any])?.count == 1)
}

@Test func aHAREntryCarriesTheRequestResponseAndTimings() throws {
    let entry = try #require(try entries([full]).first)
    let request = try child("request", of: entry)
    let response = try child("response", of: entry)
    let timings = try child("timings", of: entry)

    #expect(entry["startedDateTime"] as? String == "2023-11-14T22:13:20.250Z")
    #expect(entry["time"] as? Int == 500)
    #expect(entry["serverIPAddress"] as? String == "1.2.3.4")
    #expect(entry["connection"] == nil)
    #expect(request["method"] as? String == "POST")
    #expect(request["url"] as? String == "https://example.com/orders?page=2")
    #expect(request["httpVersion"] as? String == "h2")
    #expect(request["bodySize"] as? Int == 7)
    #expect(try child("postData", of: request)["text"] as? String == #"{"a":1}"#)
    #expect(try child("postData", of: request)["mimeType"] as? String == "application/json")
    #expect((request["queryString"] as? [[String: String]])?.first == ["name": "page", "value": "2"])
    #expect(response["status"] as? Int == 201)
    #expect((response["redirectURL"] as? String)?.isEmpty == true)
    #expect(response["bodySize"] as? Int == 2)
    #expect(try child("content", of: response)["text"] as? String == "ok")
    #expect(try child("content", of: response)["mimeType"] as? String == "text/plain")
    #expect(timings["dns"] as? Int == 10)
    #expect(timings["connect"] as? Int == 50)
    #expect(timings["ssl"] as? Int == 30)
    #expect(timings["send"] as? Int == 2)
    #expect(timings["wait"] as? Int == 98)
    #expect(timings["receive"] as? Int == 340)
    #expect(timings["blocked"] as? Int == -1)
}

@Test func timeNoStageExplainsIsBlockedOnceReceivingWasMeasured() throws {
    let queued = HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com"), method: "GET", startDate: Date()),
        timing: TransactionTiming(requestSent: 0.01, firstByte: 0.11, receive: 0.05, total: 2.16)
    )

    let timings = try child("timings", of: try #require(try entries([queued]).first))

    #expect(timings["send"] as? Int == 10)
    #expect(timings["wait"] as? Int == 100)
    #expect(timings["receive"] as? Int == 50)
    #expect(timings["blocked"] as? Int == 2_000)
}

@Test func onlyARedirectsLocationIsARedirectURL() throws {
    let redirect = HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com"), method: "GET", startDate: Date()),
        response: CapturedResponse(
            statusCode: 302, headers: [NamedValue(name: "location", value: "/next")], endDate: Date())
    )

    let response = try child("response", of: try #require(try entries([redirect]).first))

    #expect(response["redirectURL"] as? String == "/next")
}

@Test func textCutOffInsideACharacterIsStillText() throws {
    let whole = Data("héllo 🌍".utf8)
    let content = try harContent(CapturedBody(content: .truncated(whole.dropLast(2)), byteCount: 500))

    #expect(content["text"] as? String == "héllo ")
    #expect(content["encoding"] == nil)
}

@Test func completeBytesThatArentTextStayBase64EvenNearValidText() throws {
    let content = try harContent(CapturedBody(content: .complete(Data("ab".utf8) + Data([0xF0, 0x9F])), byteCount: 4))

    #expect(content["encoding"] as? String == "base64")
}

@Test func aFailedRequestIsAnEntryWithStatusZeroAndItsError() throws {
    let failed = HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com"), method: "GET", startDate: Date()),
        failure: CapturedFailure(domain: NSURLErrorDomain, code: -1_009, description: "Offline")
    )

    let entry = try #require(try entries([failed]).first)

    #expect(try child("response", of: entry)["status"] as? Int == 0)
    #expect(entry["_error"] as? String == "Offline")
    #expect(try child("timings", of: entry)["dns"] as? Int == -1)
    #expect(try child("timings", of: entry)["wait"] as? Int == 0)
}

private func withResponseBody(_ body: CapturedBody) -> HTTPTransaction {
    HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com"), method: "GET", startDate: Date()),
        response: CapturedResponse(statusCode: 200, body: body, endDate: Date())
    )
}

private func harContent(_ body: CapturedBody) throws -> [String: Any] {
    let entry = try #require(try entries([withResponseBody(body)]).first)
    return try child("content", of: try child("response", of: entry))
}

@Test func bytesThatArentTextAreBase64() throws {
    let content = try harContent(CapturedBody(content: .complete(Data([0xFF, 0x00])), byteCount: 2))

    #expect(content["text"] as? String == "/wA=")
    #expect(content["encoding"] as? String == "base64")
}

@Test func undecodedProtobufIsBase64EvenWhenItPassesForText() throws {
    let content = try harContent(
        CapturedBody(content: .complete(Data("abc".utf8)), byteCount: 3, undecoded: .noRule))

    #expect(content["text"] as? String == "YWJj")
    #expect(content["encoding"] as? String == "base64")
}

@Test func bodiesThatWerentKeptSayWhy() throws {
    #expect(
        try harContent(CapturedBody(content: .withheld, byteCount: 9))["comment"] as? String
            == "Withheld, because it couldn't be redacted.")
    #expect(try harContent(CapturedBody(content: .notStored, byteCount: 9))["comment"] as? String == "Not stored.")
    #expect(try harContent(CapturedBody(content: .withheld, byteCount: 9))["text"] == nil)
    #expect(try harContent(CapturedBody(content: .notStored, byteCount: 9))["size"] as? Int == 9)
}

@Test func truncatedAndDecodedBodiesAreMarked() throws {
    let cut = try harContent(CapturedBody(content: .truncated(Data("ab".utf8)), byteCount: 50))
    let decoded = try harContent(CapturedBody(content: .complete(Data("{}".utf8)), byteCount: 4, isDecoded: true))

    #expect(cut["text"] as? String == "ab")
    #expect(cut["comment"] as? String == "Cut off at capture, 50 bytes in all.")
    #expect(decoded["comment"] as? String == "Decoded from protobuf.")
}

@Test func anEmptySessionIsStillValidHAR() throws {
    #expect(try entries([]).isEmpty)
}

@Test func oneRequestExportsAsAJSONDocument() throws {
    let document = try object(TransactionExport.json(full))
    let request = try child("request", of: document)
    let response = try child("response", of: document)

    #expect(request["method"] as? String == "POST")
    #expect(request["startedAt"] as? String == "2023-11-14T22:13:20.250Z")
    #expect(try child("body", of: request)["text"] as? String == #"{"a":1}"#)
    #expect(try child("body", of: request)["size"] as? Int == 7)
    #expect(response["status"] as? Int == 201)
    #expect(response["mimeType"] as? String == "text/plain")
    #expect(try child("timing", of: document)["totalMilliseconds"] as? Int == 500)
    #expect(try child("timing", of: document)["tlsMilliseconds"] as? Int == 30)
    #expect(try child("connection", of: document)["remotePort"] as? Int == 443)
    #expect(try child("size", of: document)["bytesReceived"] as? Int == 300)
    #expect(document["failure"] == nil)
}

@Test func aRequestWithNothingElseStillExports() throws {
    let bare = HTTPTransaction(request: CapturedRequest(url: nil, method: "GET", startDate: Date()))

    let document = try object(TransactionExport.json(bare))

    #expect((try child("request", of: document)["url"] as? String)?.isEmpty == true)
    #expect(document["response"] == nil)
    #expect(document["timing"] == nil)
}

@Test func redactedValuesNeverReachAnExport() throws {
    let rules = RedactionRules(
        sensitiveHeaders: [.authorization], jsonKeys: ["password"], queryParameters: ["token"])
    let redactor = Redactor(rules: rules)
    let builder = TransactionBuilder(
        processor: BodyProcessor(limit: 1_000, decoders: [], redactor: redactor), redactor: redactor)
    var request = URLRequest(url: try #require(URL(string: "https://example.com/login?token=hunter2")))
    request.httpMethod = "POST"
    request.setValue("Bearer hunter2", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let exchange = RawExchange(
        id: UUID(),
        request: request,
        requestBody: Fixtures.raw(Data(#"{"password":"hunter2","user":"ada"}"#.utf8)),
        response: nil,
        responseBody: nil,
        error: nil,
        metrics: nil,
        startDate: Date(),
        endDate: Date()
    )

    let transaction = builder.transaction(from: exchange)

    for export in [TransactionExport.har([transaction]), TransactionExport.json(transaction)] {
        #expect(!export.contains("hunter2"))
        #expect(export.contains("ada"))
        #expect(export.contains(Redactor.marker))
    }
}
