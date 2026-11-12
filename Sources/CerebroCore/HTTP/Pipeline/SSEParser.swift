import Foundation

/// Splits a `text/event-stream` into events as its bytes arrive, following the WHATWG EventSource
/// format. It works on bytes, so it doesn't matter where a chunk ends: inside a line ending, a field or
/// a UTF-8 character.
struct SSEParser: Sendable {
    /// One event as parsed, before redaction.
    struct Event: Sendable, Equatable {
        /// The last event ID in effect, or `nil` if the stream hasn't set one.
        let id: String?
        let type: String
        let data: Data
    }

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let colon = UInt8(ascii: ":")
    private static let space = UInt8(ascii: " ")
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    private let limit: Int
    private var line = Data()
    private var data = Data()
    private var hasData = false
    private var type = ""
    private var lastEventID = ""
    private var isFirstLine = true

    /// Whether the last chunk ended in a carriage return, so a line feed that starts the next one
    /// belongs to the same line ending.
    private var skipsLineFeed = false

    /// Whether an unfinished line or event outgrew `limit`. Nothing is parsed after that, because the
    /// bytes that were dropped held the event boundaries.
    private(set) var hasLostFraming = false

    /// `limit` is the most an unfinished line and event may hold between them.
    init(limit: Int) {
        self.limit = limit
    }

    /// Returns the events this chunk completes, in order.
    mutating func parse(_ chunk: Data) -> [Event] {
        guard !hasLostFraming, !chunk.isEmpty else { return [] }
        var events: [Event] = []
        var rest = chunk[...]
        if skipsLineFeed, rest.first == Self.lineFeed {
            rest = rest.dropFirst()
        }
        skipsLineFeed = false
        while let end = rest.firstIndex(where: { $0 == Self.lineFeed || $0 == Self.carriageReturn }) {
            line.append(rest[..<end])
            let endsInCarriageReturn = rest[end] == Self.carriageReturn
            rest = rest[(end + 1)...]
            if endsInCarriageReturn {
                if rest.first == Self.lineFeed {
                    rest = rest.dropFirst()
                } else if rest.isEmpty {
                    skipsLineFeed = true
                }
            }
            if let event = endLine() {
                events.append(event)
            }
            guard isWithinLimit() else { return events }
        }
        line.append(rest)
        _ = isWithinLimit()
        return events
    }

    /// Stops parsing and frees what was held, for when bytes went missing before they got here.
    mutating func loseFraming() {
        hasLostFraming = true
        line = Data()
        data = Data()
    }

    private mutating func isWithinLimit() -> Bool {
        if line.count + data.count > limit {
            loseFraming()
        }
        return !hasLostFraming
    }

    private mutating func endLine() -> Event? {
        var bytes = line
        line = Data()
        if isFirstLine {
            isFirstLine = false
            if bytes.starts(with: Self.byteOrderMark) {
                bytes = bytes.dropFirst(Self.byteOrderMark.count)
            }
        }
        guard !bytes.isEmpty else { return dispatch() }
        // A line that starts with a colon is a comment, which servers send to keep a stream alive.
        guard bytes.first != Self.colon else { return nil }
        let name: Data
        var value: Data
        if let colon = bytes.firstIndex(of: Self.colon) {
            name = bytes[..<colon]
            value = bytes[(colon + 1)...]
            if value.first == Self.space {
                value = value.dropFirst()
            }
        } else {
            name = bytes
            value = Data()
        }
        apply(field: String(data: name, encoding: .utf8) ?? "", value: value)
        return nil
    }

    /// `retry` is left out on purpose: Cerebro watches the app's connection and never reconnects it.
    /// A type or ID that isn't UTF-8 is dropped, and data stays as bytes, so it's kept either way.
    private mutating func apply(field: String, value: Data) {
        switch field {
        case "data":
            if hasData {
                data.append(Self.lineFeed)
            }
            data.append(value)
            hasData = true
        case "event":
            type = String(data: value, encoding: .utf8) ?? ""
        case "id" where !value.contains(0):
            lastEventID = String(data: value, encoding: .utf8) ?? lastEventID
        default:
            break
        }
    }

    /// An empty line ends an event, which only counts if it had a `data` field.
    private mutating func dispatch() -> Event? {
        defer {
            data = Data()
            hasData = false
            type = ""
        }
        guard hasData else { return nil }
        return Event(id: lastEventID.isEmpty ? nil : lastEventID, type: type.isEmpty ? "message" : type, data: data)
    }
}
