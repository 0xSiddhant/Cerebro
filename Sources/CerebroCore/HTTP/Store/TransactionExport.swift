import Foundation

/// Captured requests as text to share. Redaction ran before storage, so an export never holds a
/// redacted value. Call these off the main thread, because a session can be large.
public enum TransactionExport {
    private typealias Object = [String: Any]

    /// One request as a JSON document: what was sent, what came back, and its metrics.
    public static func json(_ transaction: HTTPTransaction) -> String {
        var document: Object = ["request": request(of: transaction)]
        document["response"] = transaction.response.map(response)
        document["failure"] = transaction.failure.map {
            ["domain": $0.domain, "code": $0.code, "description": $0.description] as Object
        }
        document["eventStream"] = transaction.eventStream.map(eventStream)
        document["timing"] = transaction.timing.map(timing)
        document["connection"] = transaction.connection.map(connection)
        document["size"] = transaction.size.map {
            [
                "bytesSent": $0.bytesSent, "bytesReceived": $0.bytesReceived,
                "wireBodyBytes": $0.wireBodyBytes, "decodedBodyBytes": $0.decodedBodyBytes,
            ] as Object
        }
        return text(of: document)
    }

    /// A session as HAR 1.2, which browsers' developer tools and proxies such as Charles can open.
    /// `transactions` is oldest first.
    public static func har(_ transactions: [HTTPTransaction]) -> String {
        let log: Object = [
            "version": "1.2",
            // Cerebro's version isn't in its code, so this is the version of the export itself.
            "creator": ["name": "Cerebro", "version": "1"],
            "entries": transactions.map(entry),
        ]
        return text(of: ["log": log])
    }

    // MARK: - JSON document

    private static func request(of transaction: HTTPTransaction) -> Object {
        let request = transaction.request
        var object: Object = [
            "method": request.method,
            "url": request.url?.absoluteString ?? "",
            "headers": pairs(request.headers),
            "queryParameters": pairs(request.queryParameters),
            "startedAt": timestamp(request.startDate),
        ]
        object["body"] = request.body.map(body)
        return object
    }

    private static func response(_ response: CapturedResponse) -> Object {
        var object: Object = [
            "status": response.statusCode,
            "headers": pairs(response.headers),
            "endedAt": timestamp(response.endDate),
        ]
        object["mimeType"] = response.mimeType
        object["body"] = response.body.map(body)
        return object
    }

    private static func body(_ body: CapturedBody) -> Object {
        var object = content(of: body)
        object["size"] = body.byteCount
        object["contentType"] = body.contentType
        return object
    }

    private static func timing(_ timing: TransactionTiming) -> Object {
        var object: Object = ["totalMilliseconds": milliseconds(timing.total)]
        object["dnsMilliseconds"] = timing.dns.map(milliseconds)
        object["connectMilliseconds"] = timing.connect.map(milliseconds)
        object["tlsMilliseconds"] = timing.tls.map(milliseconds)
        object["requestSentMilliseconds"] = timing.requestSent.map(milliseconds)
        object["firstByteMilliseconds"] = timing.firstByte.map(milliseconds)
        return object
    }

    private static func connection(_ connection: ConnectionDetails) -> Object {
        var object: Object = [
            "isReused": connection.isReused,
            "isCellular": connection.isCellular,
            "isExpensive": connection.isExpensive,
            "isLowDataMode": connection.isConstrained,
        ]
        object["remoteAddress"] = connection.remoteAddress
        object["remotePort"] = connection.remotePort
        object["localAddress"] = connection.localAddress
        object["localPort"] = connection.localPort
        object["httpVersion"] = connection.httpVersion
        object["tlsVersion"] = connection.tlsVersion
        return object
    }

    // MARK: - HAR

    private static func entry(for transaction: HTTPTransaction) -> Object {
        let timing = transaction.timing
        var entry: Object = [
            "startedDateTime": timestamp(transaction.request.startDate),
            "time": timing.map { milliseconds($0.total) } ?? 0,
            "request": harRequest(of: transaction),
            "response": harResponse(of: transaction),
            "cache": Object(),
            "timings": harTimings(timing),
        ]
        entry["serverIPAddress"] = transaction.connection?.remoteAddress
        entry["_error"] = transaction.failure?.description
        // HAR has no field for Server-Sent Events, and a leading underscore marks a custom one.
        entry["_eventStream"] = transaction.eventStream.map(eventStream)
        return entry
    }

    private static func harRequest(of transaction: HTTPTransaction) -> Object {
        let request = transaction.request
        var object: Object = [
            "method": request.method,
            "url": request.url?.absoluteString ?? "",
            "httpVersion": transaction.connection?.httpVersion ?? "",
            "cookies": [Any](),
            "headers": pairs(request.headers),
            "queryString": pairs(request.queryParameters),
            "headersSize": -1,
            "bodySize": request.body?.byteCount ?? 0,
        ]
        if let body = request.body {
            var postData = content(of: body)
            postData["mimeType"] = body.contentType ?? ""
            postData["text"] = postData["text"] ?? ""
            object["postData"] = postData
        }
        return object
    }

    private static func harResponse(of transaction: HTTPTransaction) -> Object {
        let response = transaction.response
        var content = response?.body.map(content) ?? Object()
        content["size"] = response?.body?.byteCount ?? 0
        content["mimeType"] = response?.mimeType ?? ""
        // Other responses, such as a 201, use `Location` for something that isn't a redirect.
        let isRedirect = (300..<400).contains(response?.statusCode ?? 0)
        let location = isRedirect ? response?.headers.first { $0.name.lowercased() == "location" }?.value : nil
        return [
            // 0 is what HAR uses for a request that never got a response.
            "status": response?.statusCode ?? 0,
            "statusText": response.map { HTTPURLResponse.localizedString(forStatusCode: $0.statusCode) } ?? "",
            "httpVersion": transaction.connection?.httpVersion ?? "",
            "cookies": [Any](),
            "headers": pairs(response?.headers ?? []),
            "content": content,
            "redirectURL": location ?? "",
            "headersSize": -1,
            "bodySize": transaction.size.map { Int($0.wireBodyBytes) } ?? -1,
        ]
    }

    /// HAR wants -1 for a stage that didn't happen, except the last three, which are required.
    private static func harTimings(_ timing: TransactionTiming?) -> Object {
        guard let timing else {
            return ["blocked": -1, "dns": -1, "connect": -1, "ssl": -1, "send": 0, "wait": 0, "receive": 0]
        }
        let send = timing.requestSent ?? 0
        // `firstByte` starts when the request starts, so the wait is what's left after sending.
        let wait = max((timing.firstByte ?? 0) - send, 0)
        let before = (timing.dns ?? 0) + (timing.connect ?? 0) + send + wait
        // The total covers the whole task, so what the stages don't explain was spent waiting to start,
        // on a queue or an earlier attempt. Without a measured receive time, the two can't be told apart.
        let remainder = max(timing.total - before, 0)
        let receive = timing.receive.map { min($0, remainder) } ?? remainder
        return [
            "blocked": timing.receive == nil ? -1 : milliseconds(remainder - receive),
            "dns": timing.dns.map(milliseconds) ?? -1,
            "connect": timing.connect.map(milliseconds) ?? -1,
            "ssl": timing.tls.map(milliseconds) ?? -1,
            "send": milliseconds(send),
            "wait": milliseconds(wait),
            "receive": milliseconds(receive),
        ]
    }

    // MARK: - Shared

    /// A body's text, or why it has none. Bytes that aren't text, and protobuf that wasn't decoded and
    /// could pass for text by chance, are written as Base64.
    private static func content(of body: CapturedBody) -> Object {
        var object = Object()
        var comments: [String] = []
        if let data = body.data {
            let isTruncated = body.content == .truncated(data)
            // A body cut off at the cap can end partway through a character, which doesn't make it binary.
            if body.undecoded == nil, let text = Redactor.text(of: data, isTruncated: isTruncated) {
                object["text"] = text
            } else {
                object["text"] = data.base64EncodedString()
                object["encoding"] = "base64"
            }
        }
        switch body.content {
        case .complete: break
        case .truncated: comments.append("Cut off at capture, \(body.byteCount) bytes in all.")
        case .withheld: comments.append("Withheld, because it couldn't be redacted.")
        case .notStored: comments.append("Not stored.")
        }
        if body.isDecoded {
            comments.append("Decoded from protobuf.")
        }
        if !comments.isEmpty {
            object["comment"] = comments.joined(separator: " ")
        }
        return object
    }

    /// The same in both formats: the stream's state and counts, and each stored event.
    private static func eventStream(_ stream: CapturedEventStream) -> Object {
        [
            "state": stream.state.rawValue,
            "eventCount": stream.eventCount,
            "isTruncated": stream.isTruncated,
            "events": stream.events.map { event in
                var object: Object = [
                    "type": event.type,
                    "receivedAt": timestamp(event.date),
                    "data": body(event.data),
                ]
                object["id"] = event.id
                return object
            },
        ]
    }

    private static func pairs(_ fields: [NamedValue]) -> [Object] {
        fields.map { ["name": $0.name, "value": $0.value] }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1000).rounded())
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    private static func text(of object: Object) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try? JSONSerialization.data(withJSONObject: object, options: options)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
