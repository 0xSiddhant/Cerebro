import Foundation

/// Collects one event stream's events as its bytes arrive, redacting each before it's kept. It holds
/// the newest events up to both caps and counts all of them.
struct EventStreamAssembler: Sendable {
    /// The most events one stream keeps.
    static let eventLimit = 1_000

    private let processor: BodyProcessor
    private let context: BodyContext
    private var parser: SSEParser
    private var events: [CapturedSSEEvent] = []
    private var storedBytes = 0
    private var eventCount = 0
    private var isTruncated = false

    /// When data last arrived.
    private(set) var lastReceived: Date

    /// `url` is the request's URL, already redacted.
    init(processor: BodyProcessor, url: URL?, method: String, openedAt date: Date) {
        self.processor = processor
        // The content type marks the data as text, so no binary decoder tries it.
        context = BodyContext(url: url, method: method, contentType: "text/event-stream", direction: .response)
        parser = SSEParser(limit: processor.limit)
        lastReceived = date
    }

    /// Takes the next bytes of the response, and returns whether what `stream` reports changed.
    mutating func receive(_ chunk: Data, at date: Date) -> Bool {
        lastReceived = date
        let parsed = parser.parse(chunk)
        for event in parsed {
            append(event, at: date)
        }
        if parser.hasLostFraming, !isTruncated {
            isTruncated = true
            return true
        }
        return !parsed.isEmpty
    }

    /// Stops parsing, for when bytes were dropped before they got here.
    mutating func loseFraming() {
        parser.loseFraming()
        isTruncated = true
    }

    /// What has been captured so far.
    func stream(_ state: CapturedEventStream.State) -> CapturedEventStream {
        CapturedEventStream(state: state, eventCount: eventCount, events: events, isTruncated: isTruncated)
    }

    private mutating func append(_ event: SSEParser.Event, at date: Date) {
        eventCount += 1
        let raw = RawBody(data: event.data, limit: processor.limit)
        // Event data is text, and its first bytes could pass for a zlib header by chance.
        let data =
            processor.process(raw, context: context, detectsCompression: false)
            ?? CapturedBody(content: .complete(Data()), byteCount: 0, contentType: context.contentType)
        let captured = CapturedSSEEvent(
            id: event.id.map(redacted),
            // The default type isn't something the server sent, so it holds nothing to redact.
            type: event.type == "message" ? event.type : redacted(event.type),
            data: data,
            date: date
        )
        events.append(captured)
        storedBytes += captured.storedBytes
        while events.count > Self.eventLimit || (storedBytes > processor.limit && !events.isEmpty) {
            storedBytes -= events.removeFirst().storedBytes
            isTruncated = true
        }
    }

    /// The same rule as a socket event's text: these can't be parsed, so one that names a key goes.
    private func redacted(_ text: String) -> String {
        processor.redactor.mentionsJSONKey(in: text) ? Redactor.marker : text
    }
}

extension CapturedSSEEvent {
    fileprivate var storedBytes: Int {
        (data.data?.count ?? 0) + (id?.utf8.count ?? 0) + type.utf8.count
    }
}
