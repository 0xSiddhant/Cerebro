import Foundation

/// One Server-Sent Event, already redacted.
public struct CapturedSSEEvent: Sendable, Equatable, Codable {
    /// The last event ID in effect when the event arrived, if the stream has set one.
    public let id: String?

    /// The event's type, which is `message` unless the stream named another.
    public let type: String

    /// The event's data. An event with empty data holds an empty body.
    public let data: CapturedBody

    /// When the event's last byte arrived.
    public let date: Date

    /// Creates an event.
    public init(id: String? = nil, type: String = "message", data: CapturedBody, date: Date) {
        self.id = id
        self.type = type
        self.data = data
        self.date = date
    }
}

/// What Cerebro kept of a `text/event-stream` response.
public struct CapturedEventStream: Sendable, Equatable, Codable {
    /// Where a stream is in its life.
    public enum State: String, Sendable, Equatable, Codable {
        /// The response is still arriving.
        case open

        /// The stream ended, was cancelled or failed.
        case completed
    }

    /// Whether the stream is still arriving.
    public let state: State

    /// How many events arrived, including any no longer stored.
    public let eventCount: Int

    /// The newest events, oldest first.
    public let events: [CapturedSSEEvent]

    /// Whether events were dropped at a cap, or parsing stopped because events arrived too fast.
    public let isTruncated: Bool

    /// Creates a stream.
    public init(state: State, eventCount: Int, events: [CapturedSSEEvent], isTruncated: Bool = false) {
        self.state = state
        self.eventCount = eventCount
        self.events = events
        self.isTruncated = isTruncated
    }
}
