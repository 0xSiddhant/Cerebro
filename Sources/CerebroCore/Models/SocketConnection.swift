import Foundation

/// Which way a socket frame travelled.
public enum SocketDirection: Sendable, Equatable {
    /// From the app to the server.
    case sent

    /// From the server to the app.
    case received
}

/// What a socket frame carries, before the pipeline runs.
public enum SocketPayload: Sendable, Equatable {
    /// A text frame.
    case text(String)

    /// A binary frame.
    case binary(Data)
}

/// One message on a socket, after the pipeline ran.
public struct SocketFrame: Sendable, Equatable {
    /// What kind of frame this is.
    public enum Kind: Sendable, Equatable {
        /// A text frame.
        case text

        /// A binary frame.
        case binary
    }

    /// Which way it travelled.
    public let direction: SocketDirection

    /// Whether it was text or binary.
    public let kind: Kind

    /// The size of the whole payload, including anything not stored.
    public let byteCount: Int

    /// When it was sent or received.
    public let date: Date

    /// The stored payload, or `nil` if the frame was empty.
    public let payload: CapturedBody?

    /// Creates a frame.
    public init(direction: SocketDirection, kind: Kind, byteCount: Int, date: Date, payload: CapturedBody?) {
        self.direction = direction
        self.kind = kind
        self.byteCount = byteCount
        self.date = date
        self.payload = payload
    }
}

/// Something that happened on a socket, other than a frame.
public enum SocketEvent: Sendable, Equatable {
    /// The socket opened.
    case opened

    /// The socket closed, with the close code and reason if there were any.
    case closed(code: Int?, reason: String?)

    /// The app sent a ping.
    case ping

    /// The app's ping was answered.
    case pong

    /// The socket moved to another state, named for display.
    case stateChanged(String)

    /// The socket failed, with a description for display.
    case failed(String)
}

/// One line of a socket's timeline.
public enum SocketTimelineItem: Sendable, Equatable {
    /// A message.
    case frame(SocketFrame)

    /// Anything else that happened, and when.
    case event(SocketEvent, date: Date)

    /// When it happened.
    public var date: Date {
        switch self {
        case .frame(let frame): return frame.date
        case .event(_, let date): return date
        }
    }
}

/// How a socket's traffic reaches Cerebro.
public enum SocketSource: Sendable, Equatable {
    /// A `URLSessionWebSocketTask`, captured automatically.
    case webSocketTask

    /// An `NWConnection`, through `MonitoredNWConnection`.
    case nwConnection

    /// Any other engine, through `ExternalNetworkBridge`.
    case external
}

/// Where a socket is in its life.
public enum SocketStatus: Sendable, Equatable {
    /// It hasn't opened yet.
    case connecting

    /// It's open.
    case open

    /// It closed.
    case closed

    /// It failed.
    case failed
}

/// One socket and everything Cerebro kept of it.
public struct SocketConnection: Sendable, Equatable, Identifiable {
    /// Identifies the socket for this session.
    public let id: UUID

    /// How its traffic reached Cerebro.
    public let source: SocketSource

    /// What to call it: its URL, or the endpoint or name it was given.
    public let name: String

    /// When Cerebro first saw it.
    public let startDate: Date

    /// Where it is in its life.
    public internal(set) var status: SocketStatus

    /// How many frames it has carried, including any no longer stored.
    public internal(set) var frameCount: Int

    /// Payload bytes sent, including any no longer stored.
    public internal(set) var bytesSent: Int64

    /// Payload bytes received, including any no longer stored.
    public internal(set) var bytesReceived: Int64

    /// What's stored of its frames and events, oldest first.
    public internal(set) var timeline: [SocketTimelineItem]

    /// Creates a connection.
    public init(
        id: UUID = UUID(),
        source: SocketSource,
        name: String,
        startDate: Date,
        status: SocketStatus = .connecting,
        frameCount: Int = 0,
        bytesSent: Int64 = 0,
        bytesReceived: Int64 = 0,
        timeline: [SocketTimelineItem] = []
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.startDate = startDate
        self.status = status
        self.frameCount = frameCount
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.timeline = timeline
    }
}
