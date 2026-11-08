import Foundation
import Network
import os

/// Stands in for `NWConnection` so its state changes and frames appear in the dashboard.
///
/// Network.framework has no Objective-C methods to hook, so this is the one way to see that traffic.
/// While Cerebro is off, every call only forwards to the real connection.
public final class MonitoredNWConnection: Sendable {
    /// A closure that's told about state changes.
    public typealias StateHandler = @Sendable (NWConnection.State) -> Void

    /// The real connection, for anything this type doesn't forward.
    public let connection: NWConnection

    private let id = UUID()
    private let appStateHandler = OSAllocatedUnfairLock<StateHandler?>(initialState: nil)

    /// Creates a connection, as `NWConnection(host:port:using:)` does.
    public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters) {
        self.init(wrapping: NWConnection(host: host, port: port, using: parameters))
    }

    /// Creates a connection, as `NWConnection(to:using:)` does.
    public convenience init(to endpoint: NWEndpoint, using parameters: NWParameters) {
        self.init(wrapping: NWConnection(to: endpoint, using: parameters))
    }

    /// Monitors an existing connection.
    public init(wrapping connection: NWConnection) {
        self.connection = connection
        if SocketCaptureEngine.active != nil {
            connection.stateUpdateHandler = recordingStateHandler()
        }
    }

    /// The connection's current state.
    public var state: NWConnection.State { connection.state }

    /// The connection's endpoint.
    public var endpoint: NWEndpoint { connection.endpoint }

    /// The connection's parameters.
    public var parameters: NWParameters { connection.parameters }

    /// The connection's current path.
    public var currentPath: NWPath? { connection.currentPath }

    /// Called when the state changes.
    public var stateUpdateHandler: StateHandler? {
        get { appStateHandler.withLock { $0 } }
        set {
            appStateHandler.withLock { $0 = newValue }
            connection.stateUpdateHandler = SocketCaptureEngine.active == nil ? newValue : recordingStateHandler()
        }
    }

    /// Called when the connection's viability changes.
    public var viabilityUpdateHandler: (@Sendable (Bool) -> Void)? {
        get { connection.viabilityUpdateHandler }
        set { connection.viabilityUpdateHandler = newValue }
    }

    /// Called when a better path becomes available.
    public var betterPathUpdateHandler: (@Sendable (Bool) -> Void)? {
        get { connection.betterPathUpdateHandler }
        set { connection.betterPathUpdateHandler = newValue }
    }

    /// Called when the connection's path changes.
    public var pathUpdateHandler: (@Sendable (NWPath) -> Void)? {
        get { connection.pathUpdateHandler }
        set { connection.pathUpdateHandler = newValue }
    }

    /// Starts the connection.
    public func start(queue: DispatchQueue) {
        connection.start(queue: queue)
    }

    /// Restarts a connection that's waiting.
    public func restart() {
        connection.restart()
    }

    /// Closes the connection gracefully.
    public func cancel() {
        connection.cancel()
    }

    /// Closes the connection at once.
    public func forceCancel() {
        connection.forceCancel()
    }

    /// Cancels the current endpoint and tries the next.
    public func cancelCurrentEndpoint() {
        connection.cancelCurrentEndpoint()
    }

    /// Groups sends and receives, as `NWConnection.batch` does.
    public func batch(_ block: () -> Void) {
        connection.batch(block)
    }

    /// Sends content, as `NWConnection.send` does.
    public func send(
        content: Data?,
        contentContext: NWConnection.ContentContext = .defaultMessage,
        isComplete: Bool = true,
        completion: NWConnection.SendCompletion
    ) {
        guard let engine = SocketCaptureEngine.active else {
            connection.send(
                content: content, contentContext: contentContext, isComplete: isComplete, completion: completion)
            return
        }
        let socket = identity(with: engine)
        if let content, !content.isEmpty {
            engine.submit(.frame(.sent, Self.payload(content, in: contentContext)), on: socket)
        }
        connection.send(
            content: content,
            contentContext: contentContext,
            isComplete: isComplete,
            completion: Self.recording(completion, on: socket, with: engine)
        )
    }

    /// Receives bytes, as `NWConnection.receive` does.
    public func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: minimumIncompleteLength,
            maximumLength: maximumLength,
            completion: recording(completion)
        )
    }

    /// Receives a whole message, as `NWConnection.receiveMessage` does.
    public func receiveMessage(
        completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    ) {
        connection.receiveMessage(completion: recording(completion))
    }

    private func identity(with engine: SocketCaptureEngine) -> SocketIdentity {
        var url: URL?
        if case .url(let endpointURL) = connection.endpoint {
            url = endpointURL
        }
        return engine.identity(
            id: id,
            source: .nwConnection,
            url: url,
            fallbackName: connection.endpoint.debugDescription
        )
    }

    private func recordingStateHandler() -> StateHandler {
        { [weak self] state in
            guard let self else { return }
            if let engine = SocketCaptureEngine.active {
                engine.submit(.event(Self.event(for: state)), on: identity(with: engine))
            }
            appStateHandler.withLock { $0 }?(state)
        }
    }

    private func recording(
        _ completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    ) -> @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void {
        guard SocketCaptureEngine.active != nil else { return completion }
        return { [weak self] data, context, isComplete, error in
            if let self, let engine = SocketCaptureEngine.active {
                let socket = identity(with: engine)
                if let data, !data.isEmpty {
                    engine.submit(.frame(.received, Self.payload(data, in: context)), on: socket)
                }
                if let error {
                    engine.submit(.event(.failed(error.debugDescription)), on: socket)
                }
            }
            completion(data, context, isComplete, error)
        }
    }

    private static func recording(
        _ completion: NWConnection.SendCompletion,
        on socket: SocketIdentity,
        with engine: SocketCaptureEngine
    ) -> NWConnection.SendCompletion {
        guard case .contentProcessed(let handler) = completion else { return completion }
        return .contentProcessed { error in
            if let error {
                engine.submit(.event(.failed(error.debugDescription)), on: socket)
            }
            handler(error)
        }
    }

    private static func event(for state: NWConnection.State) -> SocketEvent {
        switch state {
        case .ready: return .opened
        case .cancelled: return .closed(code: nil, reason: nil)
        case .failed(let error): return .failed(error.debugDescription)
        case .waiting(let error): return .stateChanged("Waiting: \(error.debugDescription)")
        case .preparing: return .stateChanged("Preparing")
        case .setup: return .stateChanged("Setup")
        @unknown default: return .stateChanged("Unknown state")
        }
    }

    /// A frame is text only if WebSocket framing says so. Everything else on a raw connection is bytes.
    private static func payload(_ data: Data, in context: NWConnection.ContentContext?) -> SocketPayload {
        let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
        guard (metadata as? NWProtocolWebSocket.Metadata)?.opcode == .text,
            let text = String(data: data, encoding: .utf8)
        else { return .binary(data) }
        return .text(text)
    }
}
